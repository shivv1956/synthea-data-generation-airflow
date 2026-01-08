{{
  config(
    materialized='table',
    tags=['marts', 'fact', 'encounter']
  )
}}

/*
Marts Model: Fact Encounters
Central transactional table for healthcare encounters with star schema design
*/

WITH base_encounters AS (
  SELECT
    id,
    "START",
    "STOP",
    patient,
    organization,
    provider,
    payer,
    encounterclass,
    code,
    description,
    reasoncode,
    reasondescription,
    loaded_at
  FROM {{ ref('stg_encounters') }}
),

-- Enrich with costs from intermediate model
enriched_encounters AS (
  SELECT
    enc.*,
    COALESCE(costs.base_cost, 0.00) as base_encounter_cost,
    COALESCE(costs.total_cost, 0.00) as total_claim_cost,
    COALESCE(costs.payer_coverage, 0.00) as payer_coverage
  FROM base_encounters enc
  LEFT JOIN {{ ref('int_claims_enriched') }} costs
    ON enc.id = costs.resource_id
    AND costs.cost_type = 'encounter'
)

SELECT
  -- Primary Key
  id as encounter_id,
  
  -- Foreign Keys (to dimension tables)
  patient as patient_id,
  provider as provider_id,
  organization as organization_id,
  payer as payer_id,
  TO_NUMBER(TO_CHAR("START", 'YYYYMMDD')) as start_date_key,
  TO_NUMBER(TO_CHAR("STOP", 'YYYYMMDD')) as end_date_key,
  
  -- Encounter Attributes
  encounterclass as encounter_class,
  code,
  description,
  reasoncode as reason_code,
  reasondescription as reason_description,
  
  -- Temporal Attributes
  "START" as encounter_start_datetime,
  "STOP" as encounter_end_datetime,
  DATEDIFF(hour, "START", "STOP") as encounter_duration_hours,
  DATEDIFF(day, "START", "STOP") as encounter_duration_days,
  
  -- Financial Measures
  base_encounter_cost,
  total_claim_cost,
  payer_coverage,
  total_claim_cost - payer_coverage as patient_responsibility,
  
  -- Metadata
  loaded_at as last_updated_at
  
FROM enriched_encounters
