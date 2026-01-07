{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'careplan', 'incremental']
  )
}}

/*
Staging Model: CarePlans
Extracts care plan data from FHIR CarePlan resources
Matches Synthea CAREPLANS.CSV schema
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
  
  {% if is_incremental() %}
  WHERE loaded_at > (SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP) FROM {{ this }})
  {% endif %}
),

careplan_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'CarePlan'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_DATE(resource:period:start::STRING) as "START",
    TRY_TO_DATE(resource:period:end::STRING) as "STOP",
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    
    -- CarePlan category (typically index 1 has the specific plan type)
    COALESCE(
      resource:category[1]:coding[0]:code::STRING,
      resource:category[0]:coding[0]:code::STRING
    ) as code,
    
    COALESCE(
      resource:category[1]:coding[0]:display::STRING,
      resource:category[0]:coding[0]:display::STRING,
      resource:category[0]:text::STRING
    ) as description,
    
    -- Reason for care plan (reference to Condition)
    {{ extract_uuid_from_reference('resource:addresses[0]:reference') }} as reasoncode_ref,
    NULL as reasoncode,
    NULL as reasondescription,
    
    loaded_at
  FROM careplan_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'encounter']) }} as surrogate_key,
  *
FROM flattened
