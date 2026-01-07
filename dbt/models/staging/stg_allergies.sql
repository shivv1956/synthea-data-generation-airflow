{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'allergy', 'incremental']
  )
}}

/*
Staging Model: Allergies
Extracts allergy/intolerance data from FHIR AllergyIntolerance resources
Matches Synthea ALLERGIES.CSV schema
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

allergy_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'AllergyIntolerance'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_DATE(resource:onsetDateTime::STRING) as "START",
    TRY_TO_DATE(resource:lastOccurrence::STRING) as "STOP",
    {{ extract_uuid_from_reference('resource:patient:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    
    resource:code:coding[0]:code::STRING as code,
    resource:code:coding[0]:system::STRING as system,
    COALESCE(
      resource:code:coding[0]:display::STRING,
      resource:code:text::STRING
    ) as description,
    
    resource:type::STRING as type,
    resource:category[0]::STRING as category,
    
    -- Extract reaction information (up to 2 reactions)
    resource:reaction[0]:manifestation[0]:coding[0]:code::STRING as reaction1,
    resource:reaction[0]:manifestation[0]:coding[0]:display::STRING as description1,
    resource:reaction[0]:severity::STRING as severity1,
    
    resource:reaction[1]:manifestation[0]:coding[0]:code::STRING as reaction2,
    resource:reaction[1]:manifestation[0]:coding[0]:display::STRING as description2,
    resource:reaction[1]:severity::STRING as severity2,
    
    loaded_at
  FROM allergy_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', '"START"']) }} as surrogate_key,
  *
FROM flattened
