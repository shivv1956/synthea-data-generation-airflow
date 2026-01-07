{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'payer', 'incremental']
  )
}}

/*
Staging Model: Payers
Extracts insurance payer/plan data from FHIR Organization resources with payer type
Matches Synthea PAYERS.CSV schema
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle
  FROM {{ source('raw', 'fhir_bundles') }}
  
  {% if is_incremental() %}
  WHERE loaded_at > (SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP) FROM {{ this }})
  {% endif %}
),

-- Get Organizations that are insurance payers
payer_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Organization'
    AND (
      entry.value:resource:type[0]:coding[0]:code::STRING = 'pay'
      OR entry.value:resource:type[0]:text::STRING ILIKE '%insurance%'
      OR entry.value:resource:type[0]:text::STRING ILIKE '%payer%'
    )
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    resource:name::STRING as name,
    
    -- Ownership type (Government vs Private)
    CASE
      WHEN resource:name::STRING ILIKE '%medicare%' THEN 'Government'
      WHEN resource:name::STRING ILIKE '%medicaid%' THEN 'Government'
      WHEN resource:name::STRING ILIKE '%tricare%' THEN 'Government'
      ELSE 'Private'
    END as ownership,
    
    -- Address
    resource:address[0]:line[0]::STRING as address,
    resource:address[0]:city::STRING as city,
    resource:address[0]:state::STRING as state_headquartered,
    resource:address[0]:postalCode::STRING as zip,
    
    -- Contact
    resource:telecom[0]:value::STRING as phone,
    
    -- Financial metrics - will be calculated in marts from Claims
    0.00 as amount_covered,
    0.00 as amount_uncovered,
    0.00 as revenue,
    0 as covered_encounters,
    0 as uncovered_encounters,
    0 as covered_medications,
    0 as uncovered_medications,
    0 as covered_procedures,
    0 as uncovered_procedures,
    0 as covered_immunizations,
    0 as uncovered_immunizations,
    0 as unique_customers,
    0.00 as qols_avg,
    0 as member_months,
    
    loaded_at
  FROM payer_resources
)

SELECT * FROM flattened
