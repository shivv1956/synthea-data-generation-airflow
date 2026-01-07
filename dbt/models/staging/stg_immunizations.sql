{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'immunization', 'incremental']
  )
}}

/*
Staging Model: Immunizations
Extracts immunization/vaccination data from FHIR Immunization resources
Matches Synthea IMMUNIZATIONS.CSV schema
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

immunization_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Immunization'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_TIMESTAMP(resource:occurrenceDateTime::STRING) as date,
    {{ extract_uuid_from_reference('resource:patient:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    resource:vaccineCode:coding[0]:code::STRING as code,
    COALESCE(
      resource:vaccineCode:coding[0]:display::STRING,
      resource:vaccineCode:text::STRING
    ) as description,
    
    -- Cost will be resolved from Claims in intermediate model
    0.00 as cost,
    
    loaded_at
  FROM immunization_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'encounter']) }} as surrogate_key,
  *
FROM flattened
