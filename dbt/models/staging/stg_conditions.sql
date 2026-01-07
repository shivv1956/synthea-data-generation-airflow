{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'condition', 'incremental']
  )
}}

/*
Staging Model: Conditions
Extracts diagnosis/condition data from FHIR Condition resources
Matches Synthea CONDITIONS.CSV schema
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

condition_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Condition'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_DATE(resource:onsetDateTime::STRING) as "START",
    TRY_TO_DATE(resource:abatementDateTime::STRING) as "STOP",
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    resource:code:coding[0]:system::STRING as system,
    resource:code:coding[0]:code::STRING as code,
    COALESCE(
      resource:code:coding[0]:display::STRING,
      resource:code:text::STRING
    ) as description,
    loaded_at
  FROM condition_resources
)

SELECT 
  {{ generate_surrogate_key(['id', 'patient', 'encounter']) }} as surrogate_key,
  * 
FROM flattened
