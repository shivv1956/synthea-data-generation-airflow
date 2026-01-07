{{
  config(
    materialized='table',
    tags=['staging', 'encounter']
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
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
),

encounter_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Encounter'
),

-- Extract primary performer using LEFT JOIN
primary_performer AS (
  SELECT
    resource:id::STRING as encounter_id,
    MAX({{ extract_uuid_from_reference('participant.value:individual:reference') }}) as provider
  FROM encounter_resources,
  LATERAL FLATTEN(input => resource:participant, outer => true) participant
  WHERE participant.value:type[0]:coding[0]:code::STRING = 'PPRF'
  GROUP BY encounter_id
),

flattened AS (
  SELECT
    er.resource:id::STRING as id,
    TRY_TO_TIMESTAMP(er.resource:period:start::STRING) as "START",
    TRY_TO_TIMESTAMP(er.resource:period:end::STRING) as "STOP",
    {{ extract_uuid_from_reference('er.resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('er.resource:serviceProvider:reference') }} as organization,
    
    -- Primary performer from CTE
    pp.provider,
    
    -- Payer will be resolved from Coverage in intermediate model
    NULL as payer,
    
    er.resource:class:code::STRING as encounterclass,
    er.resource:type[0]:coding[0]:code::STRING as code,
    er.resource:type[0]:coding[0]:display::STRING as description,
    
    -- Cost fields - will be resolved from Claim resources in intermediate model
    0.00 as base_encounter_cost,
    0.00 as total_claim_cost,
    0.00 as payer_coverage,
    
    -- Reason for visit
    er.resource:reasonCode[0]:coding[0]:code::STRING as reasoncode,
    er.resource:reasonCode[0]:coding[0]:display::STRING as reasondescription,
    
    er.loaded_at
  FROM encounter_resources er
  LEFT JOIN primary_performer pp ON er.resource:id::STRING = pp.encounter_id
)

SELECT * FROM flattened
