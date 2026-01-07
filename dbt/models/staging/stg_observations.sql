{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'observation', 'incremental']
  )
}}

/*
Staging Model: Observations
Extracts lab results, vital signs, and other observations from FHIR Observation resources
Matches Synthea OBSERVATIONS.CSV schema
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

observation_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Observation'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_TIMESTAMP(resource:effectiveDateTime::STRING) as date,
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    resource:category[0]:coding[0]:code::STRING as category,
    resource:code:coding[0]:code::STRING as code,
    COALESCE(
      resource:code:coding[0]:display::STRING,
      resource:code:text::STRING
    ) as description,
    
    -- Extract value based on type
    CASE
      WHEN resource:valueQuantity:value IS NOT NULL 
        THEN resource:valueQuantity:value::STRING
      WHEN resource:valueCodeableConcept IS NOT NULL
        THEN COALESCE(
          resource:valueCodeableConcept:coding[0]:display::STRING,
          resource:valueCodeableConcept:text::STRING
        )
      WHEN resource:valueString IS NOT NULL
        THEN resource:valueString::STRING
      WHEN resource:valueBoolean IS NOT NULL
        THEN resource:valueBoolean::STRING
      ELSE NULL
    END as value,
    
    resource:valueQuantity:unit::STRING as units,
    
    -- Determine value type
    CASE
      WHEN resource:valueQuantity IS NOT NULL THEN 'numeric'
      ELSE 'text'
    END as type,
    
    loaded_at
  FROM observation_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'encounter', 'date']) }} as surrogate_key,
  *
FROM flattened
