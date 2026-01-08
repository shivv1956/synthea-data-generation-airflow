{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'lookup']
  )
}}

/*
Marts Model: Encounter Class Dimension
Lookup table for encounter class codes and descriptions
*/

WITH encounter_classes AS (
  SELECT DISTINCT
    encounterclass as encounter_class_code,
    encounterclass as encounter_class_description
  FROM {{ ref('stg_encounters') }}
  WHERE encounterclass IS NOT NULL
)

SELECT
  encounter_class_code,
  encounter_class_description,
  CASE encounter_class_code
    WHEN 'ambulatory' THEN 'Outpatient Visit'
    WHEN 'emergency' THEN 'Emergency Department'
    WHEN 'inpatient' THEN 'Hospital Admission'
    WHEN 'wellness' THEN 'Wellness / Preventive'
    WHEN 'urgentcare' THEN 'Urgent Care'
    WHEN 'outpatient' THEN 'Outpatient'
    ELSE encounter_class_code
  END as encounter_class_friendly_name,
  CASE 
    WHEN encounter_class_code IN ('inpatient', 'emergency') THEN TRUE
    ELSE FALSE
  END as is_acute_care
FROM encounter_classes
