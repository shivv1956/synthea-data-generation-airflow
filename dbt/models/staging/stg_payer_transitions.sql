{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'payer_transition', 'incremental']
  )
}}

/*
Staging Model: Payer Transitions
Extracts insurance coverage transitions from FHIR Coverage resources
Matches Synthea PAYER_TRANSITIONS.CSV schema
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

coverage_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Coverage'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    {{ extract_uuid_from_reference('resource:beneficiary:reference') }} as patient,
    resource:subscriberId::STRING as memberid,
    
    -- Extract year from period
    YEAR(TRY_TO_DATE(resource:period:start::STRING)) as start_year,
    COALESCE(
      YEAR(TRY_TO_DATE(resource:period:end::STRING)),
      9999
    ) as end_year,
    
    -- Primary payer
    {{ extract_uuid_from_reference('resource:payor[0]:reference') }} as payer,
    
    -- Secondary payer (if exists)
    {{ extract_uuid_from_reference('resource:payor[1]:reference') }} as secondary_payer,
    
    -- Relationship to subscriber
    CASE resource:relationship:coding[0]:code::STRING
      WHEN 'self' THEN 'Self'
      WHEN 'spouse' THEN 'Spouse'
      WHEN 'child' THEN 'Guardian'
      WHEN 'parent' THEN 'Guardian'
      ELSE 'Self'
    END as ownership,
    
    -- Subscriber name
    resource:subscriber:display::STRING as owner_name,
    
    loaded_at
  FROM coverage_resources
)

SELECT
  {{ generate_surrogate_key(['patient', 'payer', 'start_year']) }} as surrogate_key,
  *
FROM flattened
