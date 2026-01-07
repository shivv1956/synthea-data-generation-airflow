{{
  config(
    materialized='table',
    tags=['intermediate', 'medication_reasons', 'full_refresh']
  )
}}

/*
Intermediate Model: Medication Reasons
Resolves medication reason codes by linking MedicationRequest to Condition resources
*/

WITH medications_with_refs AS (
  SELECT
    id,
    patient,
    encounter,
    code,
    description,
    reasoncode_ref,
    loaded_at
  FROM {{ ref('stg_medications') }}
  WHERE reasoncode_ref IS NOT NULL
),

condition_lookup AS (
  SELECT
    id as condition_id,
    code as condition_code,
    description as condition_description
  FROM {{ ref('stg_conditions') }}
)

SELECT
  med.id as medication_id,
  med.patient,
  med.encounter,
  med.code as medication_code,
  med.description as medication_description,
  cond.condition_code as reasoncode,
  cond.condition_description as reasondescription,
  med.loaded_at
FROM medications_with_refs med
LEFT JOIN condition_lookup cond
  ON med.reasoncode_ref = cond.condition_id
