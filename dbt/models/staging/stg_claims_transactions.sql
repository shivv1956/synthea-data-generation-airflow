{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'claim_transaction', 'incremental']
  )
}}

/*
Staging Model: Claims Transactions
Extracts claim line items/transactions from FHIR ExplanationOfBenefit resources
Matches Synthea CLAIMS_TRANSACTIONS.CSV schema (simplified)
Note: Full transaction details require complex flattening in intermediate model
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

eob_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'ExplanationOfBenefit'
),

-- Flatten line items from ExplanationOfBenefit
line_items AS (
  SELECT
    resource:id::STRING as claim_id,
    {{ extract_uuid_from_reference('resource:patient:reference') }} as patient_id,
    {{ extract_uuid_from_reference('resource:provider:reference') }} as provider_id,
    {{ extract_uuid_from_reference('resource:facility:reference') }} as facility_id,
    resource:created::STRING as service_date,
    item.value as item_resource,
    item.index as item_sequence,
    loaded_at
  FROM eob_resources,
  LATERAL FLATTEN(input => resource:item) item
),

flattened AS (
  SELECT
    {{ generate_surrogate_key(['claim_id', 'item_sequence']) }} as id,
    claim_id as claimid,
    item_sequence as chargeid,
    patient_id as patientid,
    
    'CHARGE' as type,
    COALESCE(item_resource:net:value::FLOAT, 0.00) as amount,
    NULL as method,
    
    TRY_TO_TIMESTAMP(service_date) as fromdate,
    TRY_TO_TIMESTAMP(service_date) as todate,
    
    facility_id as placeofservice,
    item_resource:productOrService:coding[0]:code::STRING as procedurecode,
    
    NULL as modifier1,
    NULL as modifier2,
    
    -- Diagnosis references (up to 4)
    item_resource:diagnosisSequence[0]::INT as diagnosisref1,
    item_resource:diagnosisSequence[1]::INT as diagnosisref2,
    item_resource:diagnosisSequence[2]::INT as diagnosisref3,
    item_resource:diagnosisSequence[3]::INT as diagnosisref4,
    
    COALESCE(item_resource:quantity:value::INT, 1) as units,
    1 as departmentid,
    item_resource:productOrService:coding[0]:display::STRING as notes,
    COALESCE(item_resource:unitPrice:value::FLOAT, 0.00) as unitamount,
    
    NULL as transferoutid,
    NULL as transfertype,
    
    COALESCE(item_resource:adjudication[0]:amount:value::FLOAT, 0.00) as payments,
    0.00 as adjustments,
    0.00 as transfers,
    0.00 as outstanding,
    
    NULL as appointmentid,
    NULL as linenote,
    NULL as patientinsuranceid,
    1 as feescheduleid,
    provider_id as providerid,
    NULL as supervisingproviderid,
    
    loaded_at
  FROM line_items
)

SELECT * FROM flattened
