{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'provider', 'incremental']
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
    bundle
  FROM {{ source('raw', 'fhir_bundles') }}
  
  {% if is_incremental() %}
  WHERE loaded_at > (SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP) FROM {{ this }})
  {% endif %}
),

practitioner_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Practitioner'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    
    -- Organization will be resolved in intermediate model
    NULL as organization,
    
    -- Construct full name
    CONCAT_WS(' ',
      resource:name[0]:prefix[0]::STRING,
      resource:name[0]:given[0]::STRING,
      resource:name[0]:family::STRING,
      resource:name[0]:suffix[0]::STRING
    ) as name,
    
    resource:gender::STRING as gender,
    
    -- Specialty from qualification
    COALESCE(
      resource:qualification[0]:code:coding[0]:display::STRING,
      resource:qualification[0]:code:text::STRING,
      'General Practice'
    ) as speciality,
    
    -- Address
    resource:address[0]:line[0]::STRING as address,
    resource:address[0]:city::STRING as city,
    resource:address[0]:state::STRING as state,
    resource:address[0]:postalCode::STRING as zip,
    
    -- Geolocation
    (
      SELECT geo_ext.value:valueDecimal::FLOAT
      FROM LATERAL FLATTEN(input => resource:address[0]:extension) addr_ext,
           LATERAL FLATTEN(input => addr_ext.value:extension) geo_ext
      WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
        AND geo_ext.value:url::STRING = 'latitude'
      LIMIT 1
    ) as lat,
    
    (
      SELECT geo_ext.value:valueDecimal::FLOAT
      FROM LATERAL FLATTEN(input => resource:address[0]:extension) addr_ext,
           LATERAL FLATTEN(input => addr_ext.value:extension) geo_ext
      WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
        AND geo_ext.value:url::STRING = 'longitude'
      LIMIT 1
    ) as lon,
    
    -- Aggregated counts - will be calculated in marts
    0 as encounters,
    0 as procedures,
    
    loaded_at
  FROM practitioner_resources
)

SELECT * FROM flattened
