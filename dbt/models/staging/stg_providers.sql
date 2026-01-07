{{
  config(
    materialized='table',
    tags=['staging', 'provider']
  )
}}

/*
Staging Model: Providers
Extracts healthcare provider/clinician data from FHIR Practitioner resources
Matches Synthea PROVIDERS.CSV schema
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
),

practitioner_resources AS (
  SELECT
    source.file_key,

    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Practitioner'
),

-- Extract NPI identifier using LEFT JOIN
npi_identifier AS (
  SELECT
    resource:id::STRING as practitioner_id,
    MAX(id_elem.value:value::STRING) as npi
  FROM practitioner_resources,
  LATERAL FLATTEN(input => resource:identifier, outer => true) id_elem
  WHERE id_elem.value:system::STRING = 'http://hl7.org/fhir/sid/us-npi'
  GROUP BY practitioner_id
),

-- Extract geolocation using LEFT JOIN
geolocation AS (
  SELECT
    resource:id::STRING as practitioner_id,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'latitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lat,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'longitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lon
  FROM practitioner_resources,
  LATERAL FLATTEN(input => resource:address[0]:extension, outer => true) addr_ext,
  LATERAL FLATTEN(input => addr_ext.value:extension, outer => true) geo_ext
  WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
  GROUP BY practitioner_id
),

flattened AS (
  SELECT
    -- NPI from CTE
    npi.npi as id,
    
    -- Organization will be resolved in intermediate model
    NULL as organization,
    
    -- Construct full name
    CONCAT_WS(' ',
      pr.resource:name[0]:prefix[0]::STRING,
      pr.resource:name[0]:given[0]::STRING,
      pr.resource:name[0]:family::STRING,
      pr.resource:name[0]:suffix[0]::STRING
    ) as name,
    
    pr.resource:gender::STRING as gender,
    
    -- Specialty from qualification
    COALESCE(
      pr.resource:qualification[0]:code:coding[0]:display::STRING,
      pr.resource:qualification[0]:code:text::STRING,
      'General Practice'
    ) as speciality,
    
    -- Address
    pr.resource:address[0]:line[0]::STRING as address,
    pr.resource:address[0]:city::STRING as city,
    pr.resource:address[0]:state::STRING as state,
    pr.resource:address[0]:postalCode::STRING as zip,
    
    -- Geolocation from CTE
    g.lat,
    g.lon,
    
    -- Aggregated counts - will be calculated in marts
    0 as encounters,
    0 as procedures,
    
    pr.loaded_at
  FROM practitioner_resources pr
  LEFT JOIN npi_identifier npi ON pr.resource:id::STRING = npi.practitioner_id
  LEFT JOIN geolocation g ON pr.resource:id::STRING = g.practitioner_id
)

SELECT * FROM flattened
