{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'device', 'incremental']
  )
}}

/*
Staging Model: Devices
Extracts medical device data from FHIR Device resources
Matches Synthea DEVICES.CSV schema
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

-- First get Device resources for UDI and type information
device_definitions AS (
  SELECT
    entry.value:resource:id::STRING as device_id,
    entry.value:resource:type:coding[0]:code::STRING as code,
    COALESCE(
      entry.value:resource:type:coding[0]:display::STRING,
      entry.value:resource:type:text::STRING
    ) as description,
    entry.value:resource:udiCarrier[0]:deviceIdentifier::STRING as udi
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Device'
),

-- Then get DeviceUseStatement for patient association and timing
device_use_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING IN ('DeviceUseStatement', 'DeviceRequest')
),

flattened AS (
  SELECT
    resource:id::STRING as id,
    TRY_TO_TIMESTAMP(
      COALESCE(
        resource:timingDateTime::STRING,
        resource:timingPeriod:start::STRING,
        resource:authoredOn::STRING
      )
    ) as "START",
    TRY_TO_TIMESTAMP(resource:timingPeriod:end::STRING) as "STOP",
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:context:reference') }} as encounter,
    
    -- Get device details
    {{ extract_uuid_from_reference('resource:device:reference') }} as device_ref,
    COALESCE(
      resource:device:display::STRING,
      resource:codeCodeableConcept:coding[0]:code::STRING
    ) as code,
    COALESCE(
      resource:device:display::STRING,
      resource:codeCodeableConcept:coding[0]:display::STRING
    ) as description,
    NULL as udi,  -- Will be joined from device_definitions in intermediate model
    
    loaded_at
  FROM device_use_resources
)

SELECT
  {{ generate_surrogate_key(['id', 'patient']) }} as surrogate_key,
  *
FROM flattened
