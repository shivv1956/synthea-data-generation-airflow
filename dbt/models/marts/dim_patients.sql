{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'patient']
  )
}}

/*
Marts Model: Patient Dimension
Analytics-ready patient demographics with calculated fields and enrichments
*/

WITH base_patients AS (
  SELECT
    id,
    birthdate,
    deathdate,
    ssn,
    drivers,
    passport,
    prefix,
    first,
    middle,
    last,
    suffix,
    maiden,
    marital,
    race,
    ethnicity,
    gender,
    birthplace,
    address,
    city,
    state,
    county,
    zip,
    lat,
    lon,
    loaded_at
  FROM {{ ref('stg_patients') }}
),

-- Calculate age
with_age AS (
  SELECT
    *,
    CASE
      WHEN deathdate IS NOT NULL 
        THEN DATEDIFF(year, birthdate, deathdate)
      ELSE DATEDIFF(year, birthdate, CURRENT_DATE())
    END as age,
    CASE
      WHEN deathdate IS NULL THEN TRUE
      ELSE FALSE
    END as is_alive
  FROM base_patients
),

-- Calculate healthcare expenses (aggregate from claims)
patient_expenses AS (
  SELECT
    patient_id,
    SUM(total_cost) as total_healthcare_expenses,
    SUM(payer_coverage) as total_healthcare_coverage
  FROM {{ ref('int_claims_enriched') }}
  WHERE patient_id IS NOT NULL
  GROUP BY 1
)

SELECT
  p.id as patient_key,
  p.ssn,
  p.drivers as drivers_license,
  p.passport,
  
  -- Name
  p.prefix,
  p.first as first_name,
  p.middle as middle_name,
  p.last as last_name,
  p.suffix,
  p.maiden as maiden_name,
  CONCAT_WS(' ', p.prefix, p.first, p.middle, p.last, p.suffix) as full_name,
  
  -- Demographics
  p.gender,
  p.birthdate as birth_date,
  p.deathdate as death_date,
  p.age,
  p.is_alive,
  p.marital as marital_status,
  p.race,
  p.ethnicity,
  p.birthplace,
  
  -- Address
  p.address,
  p.city,
  p.state,
  p.county,
  p.zip as zip_code,
  p.lat as latitude,
  p.lon as longitude,
  
  -- Financial
  COALESCE(exp.total_healthcare_expenses, 0.00) as lifetime_healthcare_expenses,
  COALESCE(exp.total_healthcare_coverage, 0.00) as lifetime_healthcare_coverage,
  COALESCE(exp.total_healthcare_expenses - exp.total_healthcare_coverage, 0.00) as patient_out_of_pocket,
  
  -- Metadata
  p.loaded_at as last_updated_at
  
FROM with_age p
LEFT JOIN patient_expenses exp
  ON p.id = exp.patient_id
