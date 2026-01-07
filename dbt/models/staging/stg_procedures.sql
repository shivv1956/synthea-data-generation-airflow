{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'procedure', 'incremental']
  )
}}

/*
Staging Model: Procedures
Extracts procedure data from FHIR Procedure resources
Matches Synthea PROCEDURES.CSV schema
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

procedure_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Procedure'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    
    COALESCE(
      TRY_TO_TIMESTAMP(resource:performedPeriod:start::STRING),
      TRY_TO_TIMESTAMP(resource:performedDateTime::STRING)
    ) as "START",
    
    TRY_TO_TIMESTAMP(resource:performedPeriod:end::STRING) as "STOP",
    
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    
    resource:code:coding[0]:system::STRING as system,
    resource:code:coding[0]:code::STRING as code,
    COALESCE(
      resource:code:coding[0]:display::STRING,
      resource:code:text::STRING
    ) as description,
    
    -- Cost will be resolved from Claims in intermediate model
    0.00 as base_cost,
    
    -- Reason for procedure (reference to Condition)
    {{ extract_uuid_from_reference('resource:reasonReference[0]:reference') }} as reasoncode_ref,
    NULL as reasoncode,
    NULL as reasondescription,
    
    loaded_at
  FROM procedure_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'encounter']) }} as surrogate_key,
  *
FROM flattened
