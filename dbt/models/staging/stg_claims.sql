{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'claim', 'incremental']
  )
}}

/*
Staging Model: Claims
Extracts insurance claim data from FHIR Claim and ExplanationOfBenefit resources
Matches Synthea CLAIMS.CSV schema (simplified)
Note: Full claims data requires complex aggregation in intermediate model
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
  
  {% if is_incremental() %}
  WHERE loaded_at > (SELECT COALESCE(MAX(loaded_at), '1900-01-01'::TIMESTAMP) FROM {{ this }})
  {% endif %}
),

-- Extract from ExplanationOfBenefit (more complete than Claim)
eob_resources AS (
  SELECT
    source.file_key,

    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'ExplanationOfBenefit'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    {{ extract_uuid_from_reference('resource:patient:reference') }} as patientid,
    {{ extract_uuid_from_reference('resource:provider:reference') }} as providerid,
    {{ extract_uuid_from_reference('resource:insurance[0]:coverage:reference') }} as primarypatientinsuranceid,
    {{ extract_uuid_from_reference('resource:insurance[1]:coverage:reference') }} as secondarypatientinsuranceid,
    
    -- Placeholder department fields
    1 as departmentid,
    1 as patientdepartmentid,
    
    -- Diagnosis codes (up to 8)
    resource:diagnosis[0]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis1,
    resource:diagnosis[1]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis2,
    resource:diagnosis[2]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis3,
    resource:diagnosis[3]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis4,
    resource:diagnosis[4]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis5,
    resource:diagnosis[5]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis6,
    resource:diagnosis[6]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis7,
    resource:diagnosis[7]:diagnosisCodeableConcept:coding[0]:code::STRING as diagnosis8,
    
    NULL as referringproviderid,
    {{ extract_uuid_from_reference('resource:claim:reference') }} as appointmentid,
    
    TRY_TO_TIMESTAMP(resource:created::STRING) as currentillnessdate,
    TRY_TO_TIMESTAMP(resource:billablePeriod:start::STRING) as servicedate,
    
    NULL as supervisingproviderid,
    
    -- Status fields
    resource:status::STRING as status1,
    NULL as status2,
    'CLOSED' as statusp,
    
    -- Financial amounts
    COALESCE(resource:total[0]:amount:value::FLOAT, 0.00) as outstanding1,
    0.00 as outstanding2,
    COALESCE(resource:payment:amount:value::FLOAT, 0.00) as outstandingp,
    
    TRY_TO_TIMESTAMP(resource:created::STRING) as lastbilleddate1,
    NULL as lastbilleddate2,
    TRY_TO_TIMESTAMP(resource:created::STRING) as lastbilleddatep,
    
    CASE resource:type:coding[0]:code::STRING
      WHEN 'professional' THEN 1
      WHEN 'institutional' THEN 2
      ELSE 1
    END as healthcareclaimtypeid1,
    
    NULL as healthcareclaimtypeid2,
    
    loaded_at
  FROM eob_resources
)

SELECT * FROM flattened
