{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'supply', 'incremental']
  )
}}

/*
Staging Model: Supplies
Extracts medical supply data from FHIR SupplyDelivery resources
Matches Synthea SUPPLIES.CSV schema
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

supply_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'SupplyDelivery'
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_DATE(resource:occurrenceDateTime::STRING) as date,
    {{ extract_uuid_from_reference('resource:patient:reference') }} as patient,
    
    -- Encounter may not be directly linked, will be resolved in intermediate
    {{ extract_uuid_from_reference('resource:destination:reference') }} as encounter,
    
    resource:suppliedItem:itemCodeableConcept:coding[0]:code::STRING as code,
    COALESCE(
      resource:suppliedItem:itemCodeableConcept:coding[0]:display::STRING,
      resource:suppliedItem:itemCodeableConcept:text::STRING
    ) as description,
    
    COALESCE(
      resource:suppliedItem:quantity:value::INT,
      1
    ) as quantity,
    
    loaded_at
  FROM supply_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient', 'date']) }} as surrogate_key,
  *
FROM flattened
