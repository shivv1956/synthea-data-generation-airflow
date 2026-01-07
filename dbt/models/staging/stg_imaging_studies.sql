{{
  config(
    materialized='incremental',
    unique_key='id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    tags=['staging', 'imaging', 'incremental']
  )
}}

/*
Staging Model: Imaging Studies
Extracts radiology/imaging study data from FHIR ImagingStudy resources
Matches Synthea IMAGING_STUDIES.CSV schema
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

imaging_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'ImagingStudy'
),

-- Flatten series and instances from ImagingStudy
series_flattened AS (
  SELECT
    resource:id::STRING as study_id,
    TRY_TO_TIMESTAMP(resource:started::STRING) as date,
    {{ extract_uuid_from_reference('resource:subject:reference') }} as patient,
    {{ extract_uuid_from_reference('resource:encounter:reference') }} as encounter,
    
    series.value:uid::STRING as series_uid,
    series.value:bodySite:code::STRING as bodysite_code,
    series.value:bodySite:display::STRING as bodysite_description,
    series.value:modality:code::STRING as modality_code,
    series.value:modality:display::STRING as modality_description,
    
    instance.value:uid::STRING as instance_uid,
    instance.value:sopClass:code::STRING as sop_code,
    instance.value:sopClass:display::STRING as sop_description,
    
    loaded_at
  FROM imaging_resources,
  LATERAL FLATTEN(input => resource:series) series,
  LATERAL FLATTEN(input => series.value:instance) instance
),

flattened AS (
  SELECT
    {{ generate_surrogate_key(['study_id', 'series_uid', 'instance_uid']) }} as id,
    study_id,
    date,
    patient,
    encounter,
    series_uid,
    bodysite_code as bodysitecode,
    bodysite_description as bodysitedescription,
    modality_code as modalitycode,
    modality_description as modalitydescription,
    instance_uid,
    sop_code as sopcode,
    sop_description as sopdescription,
    NULL as procedurecode,  -- Will be linked from Procedure in intermediate
    loaded_at
  FROM series_flattened
)

SELECT * FROM flattened
