{{
  config(
    materialized='table',
    tags=['intermediate', 'reference', 'full_refresh']
  )
}}

/*
Intermediate Model: Reference Map
Creates a lookup table for resolving FHIR UUID references to actual resource data
Full refresh to ensure all references are up-to-date
*/

WITH all_resources AS (
  -- Patients
  SELECT
    id as resource_id,
    'Patient' as resource_type,
    id as patient_id,
    NULL as encounter_id,
    NULL as condition_id,
    first || ' ' || last as display_name,
    loaded_at
  FROM {{ ref('stg_patients') }}
  
  UNION ALL
  
  -- Encounters
  SELECT
    id as resource_id,
    'Encounter' as resource_type,
    patient as patient_id,
    id as encounter_id,
    NULL as condition_id,
    description as display_name,
    loaded_at
  FROM {{ ref('stg_encounters') }}
  
  UNION ALL
  
  -- Conditions
  SELECT
    id as resource_id,
    'Condition' as resource_type,
    patient as patient_id,
    encounter as encounter_id,
    code as condition_id,
    description as display_name,
    loaded_at
  FROM {{ ref('stg_conditions') }}
  
  UNION ALL
  
  -- Providers
  SELECT
    id as resource_id,
    'Practitioner' as resource_type,
    NULL as patient_id,
    NULL as encounter_id,
    NULL as condition_id,
    name as display_name,
    loaded_at
  FROM {{ ref('stg_providers') }}
  
  UNION ALL
  
  -- Organizations
  SELECT
    id as resource_id,
    'Organization' as resource_type,
    NULL as patient_id,
    NULL as encounter_id,
    NULL as condition_id,
    name as display_name,
    loaded_at
  FROM {{ ref('stg_organizations') }}
  
  UNION ALL
  
  -- Payers
  SELECT
    id as resource_id,
    'Payer' as resource_type,
    NULL as patient_id,
    NULL as encounter_id,
    NULL as condition_id,
    name as display_name,
    loaded_at
  FROM {{ ref('stg_payers') }}
)

SELECT
  resource_id,
  resource_type,
  patient_id,
  encounter_id,
  condition_id,
  display_name,
  MAX(loaded_at) as last_updated
FROM all_resources
GROUP BY 1,2,3,4,5,6
