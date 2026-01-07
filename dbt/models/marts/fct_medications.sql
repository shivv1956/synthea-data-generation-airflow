{{
  config(
    materialized='table',
    tags=['marts', 'fact', 'medication']
  )
}}

/*
Marts Model: Medications Fact Table
Prescription medication data with resolved reasons and costs
*/

WITH base_medications AS (
  SELECT
    id,
    "START",
    "STOP",
    patient,
    encounter,
    code,
    description,
    dispenses,
    loaded_at
  FROM {{ ref('stg_medications') }}
),

-- Enrich with reason codes
with_reasons AS (
  SELECT
    med.*,
    reasons.reasoncode,
    reasons.reasondescription
  FROM base_medications med
  LEFT JOIN {{ ref('int_medication_reasons') }} reasons
    ON med.id = reasons.medication_id
),

-- Enrich with costs
with_costs AS (
  SELECT
    med.*,
    COALESCE(costs.base_cost, 0.00) as base_cost,
    COALESCE(costs.payer_coverage, 0.00) as payer_coverage,
    COALESCE(costs.total_cost, 0.00) as total_cost
  FROM with_reasons med
  LEFT JOIN {{ ref('int_claims_enriched') }} costs
    ON med.id = costs.resource_id
    AND costs.cost_type = 'medication'
)

SELECT
  id as medication_key,
  patient as patient_id,
  encounter as encounter_id,
  
  -- Medication details
  code as medication_code,
  description as medication_description,
  "START" as prescription_start,
  "STOP" as prescription_stop,
  DATEDIFF(day, "START", "STOP") as prescription_duration_days,
  dispenses as number_of_dispenses,
  
  -- Reason for medication
  reasoncode as reason_code,
  reasondescription as reason_description,
  
  -- Financial
  base_cost as cost_per_dispense,
  total_cost,
  payer_coverage,
  total_cost - payer_coverage as patient_responsibility,
  
  -- Metadata
  loaded_at as last_updated_at
  
FROM with_costs
