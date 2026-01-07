{{
  config(
    materialized='table',
    tags=['staging', 'organization']
  )
}}

/*
Staging Model: Organizations
Extracts healthcare organization/facility data from FHIR Organization resources
Matches Synthea ORGANIZATIONS.CSV schema
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
),

organization_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Organization'
),

-- Extract geolocation using LEFT JOIN
geolocation AS (
  SELECT
    resource:id::STRING as org_id,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'latitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lat,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'longitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lon
  FROM organization_resources,
  LATERAL FLATTEN(input => resource:address[0]:extension, outer => true) addr_ext,
  LATERAL FLATTEN(input => addr_ext.value:extension, outer => true) geo_ext
  WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
  GROUP BY org_id
),

flattened AS (
  SELECT
    org.resource:id::STRING as id,
    org.resource:name::STRING as name,
    
    -- Address
    org.resource:address[0]:line[0]::STRING as address,
    org.resource:address[0]:city::STRING as city,
    org.resource:address[0]:state::STRING as state,
    org.resource:address[0]:postalCode::STRING as zip,
    
    -- Geolocation from CTE
    g.lat,
    g.lon,
    
    -- Contact
    org.resource:telecom[0]:value::STRING as phone,
    
    -- Financial aggregates - will be calculated in marts
    0.00 as revenue,
    0 as utilization,
    
    org.loaded_at
  FROM organization_resources org
  LEFT JOIN geolocation g ON org.resource:id::STRING = g.org_id
)

SELECT * FROM flattened
