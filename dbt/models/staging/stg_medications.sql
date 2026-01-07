{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'medication', 'incremental']
  )
}}

/*
Staging Model: Medications
Extracts medication prescription data from FHIR MedicationRequest resources
Matches Synthea MEDICATIONS.CSV schema
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

medication_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'MedicationRequest'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_TIMESTAMP(resource:authoredOn::STRING) as "START",
    
    -- Stop date from dispense or null
    TRY_TO_TIMESTAMP(
      resource:dispenseRequest:validityPeriod:end::STRING
    ) as "STOP",
    
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    
    -- Payer will be resolved from Claims in intermediate model
    NULL as payer,
    
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    
    COALESCE(
      resource:medicationCodeableConcept:coding[0]:code::STRING,
      {{ extract_uuid_from_reference('resource:medicationReference:reference') }}
    ) as code,
    
    COALESCE(
      resource:medicationCodeableConcept:coding[0]:display::STRING,
      resource:medicationCodeableConcept:text::STRING
    ) as description,
    
    -- Cost fields - will be resolved from Claim resources in intermediate model
    0.00 as base_cost,
    0.00 as payer_coverage,
    COALESCE(
      resource:dispenseRequest:numberOfRepeatsAllowed::INT,
      1
    ) as dispenses,
    0.00 as totalcost,
    
    -- Reason for medication (reference to Condition)
    {{ extract_uuid_from_reference('resource:reasonReference[0]:reference') }} as reasoncode_ref,
    NULL as reasoncode,
    NULL as reasondescription,
    
    loaded_at
  FROM medication_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'encounter']) }} as surrogate_key,
  *
FROM flattened
