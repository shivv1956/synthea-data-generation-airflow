{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'organization', 'incremental']
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
    bundle
  FROM {{ source('raw', 'fhir_bundles') }}
  
  {% if is_incremental() %}
  WHERE loaded_at > (SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP) FROM {{ this }})
  {% endif %}
),

organization_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Organization'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    resource:name::STRING as name,
    
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
    
    -- Contact
    resource:telecom[0]:value::STRING as phone,
    
    -- Financial aggregates - will be calculated in marts
    0.00 as revenue,
    0 as utilization,
    
    loaded_at
  FROM organization_resources
)

SELECT * FROM flattened
