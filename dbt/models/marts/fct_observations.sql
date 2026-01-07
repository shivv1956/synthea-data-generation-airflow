{{
  config(
    materialized='table',
    tags=['marts', 'fact', 'observation']
  )
}}

/*
Marts Model: Observations Fact Table
Lab results, vital signs, and other clinical observations
*/

WITH base_observations AS (
  SELECT
    id,
    date,
    patient,
    encounter,
    category,
    code,
    description,
    value,
    units,
    type,
    loaded_at
  FROM {{ ref('stg_observations') }}
)

SELECT
  {{ dbt_utils.generate_surrogate_key(['id', 'date', 'patient']) }} as observation_key,
  patient as patient_id,
  encounter as encounter_id,
  
  -- Observation details
  date as observation_date,
  category as observation_category,
  code as observation_code,
  description as observation_description,
  
  -- Value
  value as observation_value,
  units as observation_units,
  type as value_type,
  
  -- Parse numeric values
  CASE 
    WHEN type = 'numeric' THEN TRY_CAST(value AS FLOAT)
    ELSE NULL
  END as numeric_value,
  
  -- Metadata
  loaded_at as last_updated_at
  
FROM base_observations
