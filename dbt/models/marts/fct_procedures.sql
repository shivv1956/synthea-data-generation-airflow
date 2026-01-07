{{
  config(
    materialized='table',
    tags=['marts', 'fact', 'procedure']
  )
}}

/*
Marts Model: Procedures Fact Table
Medical procedure data with resolved reasons and costs
*/

WITH base_procedures AS (
  SELECT
    id,
    "START",
    "STOP",
    patient,
    encounter,
    system,
    code,
    description,
    loaded_at
  FROM {{ ref('stg_procedures') }}
),

-- Enrich with reason codes
with_reasons AS (
  SELECT
    proc.*,
    reasons.reasoncode,
    reasons.reasondescription
  FROM base_procedures proc
  LEFT JOIN {{ ref('int_procedure_reasons') }} reasons
    ON proc.id = reasons.procedure_id
),

-- Enrich with costs
with_costs AS (
  SELECT
    proc.*,
    COALESCE(costs.base_cost, 0.00) as base_cost
  FROM with_reasons proc
  LEFT JOIN {{ ref('int_claims_enriched') }} costs
    ON proc.id = costs.resource_id
    AND costs.cost_type = 'procedure'
)

SELECT
  id as procedure_key,
  patient as patient_id,
  encounter as encounter_id,
  
  -- Procedure details
  system as code_system,
  code as procedure_code,
  description as procedure_description,
  "START" as procedure_start,
  "STOP" as procedure_stop,
  DATEDIFF(minute, "START", "STOP") as procedure_duration_minutes,
  
  -- Reason for procedure
  reasoncode as reason_code,
  reasondescription as reason_description,
  
  -- Financial
  base_cost,
  
  -- Metadata
  loaded_at as last_updated_at
  
FROM with_costs
