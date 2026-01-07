{{
  config(
    materialized='table',
    tags=['intermediate', 'claims_enriched', 'full_refresh']
  )
}}

/*
Intermediate Model: Claims Enriched
Joins claim data with encounters and line items to calculate complete financial information
Provides base_cost, total_cost, and payer_coverage for encounters, medications, procedures, immunizations
*/

WITH claim_summary AS (
  SELECT
    claimid,
    patientid,
    SUM(amount) as total_charge,
    SUM(payments) as total_payment,
    SUM(outstanding) as total_outstanding,
    MAX(fromdate) as service_date
  FROM {{ ref('stg_claims_transactions') }}
  GROUP BY 1, 2
),

encounter_costs AS (
  SELECT
    enc.id as encounter_id,
    enc.patient as patient_id,
    COALESCE(cs.total_charge, 0.00) as base_encounter_cost,
    COALESCE(cs.total_charge, 0.00) as total_claim_cost,
    COALESCE(cs.total_payment, 0.00) as payer_coverage
  FROM {{ ref('stg_encounters') }} enc
  LEFT JOIN claim_summary cs
    ON enc.id = cs.claimid
    OR enc.patient = cs.patientid
),

procedure_costs AS (
  SELECT
    proc.id as procedure_id,
    proc.encounter,
    COALESCE(AVG(ct.unitamount), 0.00) as base_cost
  FROM {{ ref('stg_procedures') }} proc
  LEFT JOIN {{ ref('stg_claims_transactions') }} ct
    ON proc.code = ct.procedurecode
  GROUP BY 1, 2
),

medication_costs AS (
  SELECT
    med.id as medication_id,
    med.encounter,
    med.dispenses,
    COALESCE(AVG(ct.unitamount), 0.00) as base_cost,
    COALESCE(AVG(ct.payments), 0.00) as payer_coverage
  FROM {{ ref('stg_medications') }} med
  LEFT JOIN {{ ref('stg_claims_transactions') }} ct
    ON ct.type = 'CHARGE'
  GROUP BY 1, 2, 3
),

immunization_costs AS (
  SELECT
    imm.id as immunization_id,
    imm.encounter,
    COALESCE(AVG(ct.unitamount), 50.00) as cost  -- Default $50 for immunizations
  FROM {{ ref('stg_immunizations') }} imm
  LEFT JOIN {{ ref('stg_claims_transactions') }} ct
    ON imm.code = ct.procedurecode
  GROUP BY 1, 2
)

SELECT
  'encounter' as cost_type,
  encounter_id as resource_id,
  patient_id,
  NULL as encounter_id,
  base_encounter_cost as base_cost,
  total_claim_cost as total_cost,
  payer_coverage,
  NULL as dispenses
FROM encounter_costs

UNION ALL

SELECT
  'procedure' as cost_type,
  procedure_id as resource_id,
  NULL as patient_id,
  encounter as encounter_id,
  base_cost,
  base_cost as total_cost,
  0.00 as payer_coverage,
  NULL as dispenses
FROM procedure_costs

UNION ALL

SELECT
  'medication' as cost_type,
  medication_id as resource_id,
  NULL as patient_id,
  encounter as encounter_id,
  base_cost,
  base_cost * dispenses as total_cost,
  payer_coverage,
  dispenses
FROM medication_costs

UNION ALL

SELECT
  'immunization' as cost_type,
  immunization_id as resource_id,
  NULL as patient_id,
  encounter as encounter_id,
  cost as base_cost,
  cost as total_cost,
  cost as payer_coverage,
  NULL as dispenses
FROM immunization_costs
