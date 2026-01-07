{{
  config(
    materialized='table',
    tags=['intermediate', 'procedure_reasons', 'full_refresh']
  )
}}

/*
Intermediate Model: Procedure Reasons
Resolves procedure reason codes by linking Procedure to Condition resources
*/

WITH procedures_with_refs AS (
  SELECT
    id,
    patient,
    encounter,
    code,
    description,
    reasoncode_ref,
    loaded_at
  FROM {{ ref('stg_procedures') }}
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
  proc.id as procedure_id,
  proc.patient,
  proc.encounter,
  proc.code as procedure_code,
  proc.description as procedure_description,
  cond.condition_code as reasoncode,
  cond.condition_description as reasondescription,
  proc.loaded_at
FROM procedures_with_refs proc
LEFT JOIN condition_lookup cond
  ON proc.reasoncode_ref = cond.condition_id
