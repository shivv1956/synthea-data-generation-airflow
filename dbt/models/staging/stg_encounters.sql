{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'encounter', 'incremental']
  )
}}

/*
Staging Model: Encounters
Extracts encounter/visit data from FHIR Encounter resources
Matches Synthea ENCOUNTERS.CSV schema
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

encounter_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Encounter'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_TIMESTAMP(resource:period:start::STRING) as "START",
    TRY_TO_TIMESTAMP(resource:period:end::STRING) as "STOP",
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:serviceProvider:reference') }} as organization,
    {{ extract_uuid_from_reference('resource:participant[0]:individual:reference') }} as provider,
    
    -- Payer will be resolved from Coverage in intermediate model
    NULL as payer,
    
    resource:class:code::STRING as encounterclass,
    resource:type[0]:coding[0]:code::STRING as code,
    resource:type[0]:coding[0]:display::STRING as description,
    
    -- Cost fields - will be resolved from Claim resources in intermediate model
    0.00 as base_encounter_cost,
    0.00 as total_claim_cost,
    0.00 as payer_coverage,
    
    -- Reason for visit
    resource:reasonCode[0]:coding[0]:code::STRING as reasoncode,
    resource:reasonCode[0]:coding[0]:display::STRING as reasondescription,
    
    loaded_at
  FROM encounter_resources
)

SELECT * FROM flattened
