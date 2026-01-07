{{
  config(
    materialized='table',
    tags=['staging', 'patient']
  )
}}

/*
Staging Model: Patients
Extracts patient demographics from FHIR Patient resources
Matches Synthea PATIENTS.CSV schema
*/

WITH source AS (
  SELECT
    file_key,
    loaded_at,
    bundle_data
  FROM {{ source('raw', 'fhir_bundles') }}
),

patient_resources AS (
  SELECT
    source.file_key,
    source.loaded_at,
    entry.value:resource AS resource
  FROM source,
  LATERAL FLATTEN(input => source.bundle_data:entry) entry
  WHERE entry.value:resource:resourceType::STRING = 'Patient'
),

-- Extract identifiers using LEFT JOIN
identifiers AS (
  SELECT
    resource:id::STRING as patient_id,
    MAX(CASE WHEN id_elem.value:type:coding[0]:code::STRING = 'SS' THEN id_elem.value:value::STRING END) as ssn,
    MAX(CASE WHEN id_elem.value:type:coding[0]:code::STRING = 'DL' THEN id_elem.value:value::STRING END) as drivers,
    MAX(CASE WHEN id_elem.value:type:coding[0]:code::STRING = 'PPN' THEN id_elem.value:value::STRING END) as passport
  FROM patient_resources,
  LATERAL FLATTEN(input => resource:identifier, outer => true) id_elem
  GROUP BY patient_id
),

-- Extract extensions using LEFT JOIN
extensions AS (
  SELECT
    resource:id::STRING as patient_id,
    MAX(CASE WHEN ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/patient-mothersMaidenName' 
             THEN ext.value:valueString::STRING END) as maiden,
    MAX(CASE WHEN ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/patient-birthPlace' 
             THEN ext.value:valueAddress:city::STRING END) as birthplace
  FROM patient_resources,
  LATERAL FLATTEN(input => resource:extension, outer => true) ext
  GROUP BY patient_id
),

-- Extract race from nested extension
race_ext AS (
  SELECT
    resource:id::STRING as patient_id,
    MAX(CASE WHEN child_ext.value:url::STRING = 'text' THEN child_ext.value:valueString::STRING END) as race
  FROM patient_resources,
  LATERAL FLATTEN(input => resource:extension, outer => true) parent_ext,
  LATERAL FLATTEN(input => parent_ext.value:extension, outer => true) child_ext
  WHERE parent_ext.value:url::STRING = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race'
  GROUP BY patient_id
),

-- Extract ethnicity from nested extension
ethnicity_ext AS (
  SELECT
    resource:id::STRING as patient_id,
    MAX(CASE WHEN child_ext.value:url::STRING = 'text' THEN child_ext.value:valueString::STRING END) as ethnicity
  FROM patient_resources,
  LATERAL FLATTEN(input => resource:extension, outer => true) parent_ext,
  LATERAL FLATTEN(input => parent_ext.value:extension, outer => true) child_ext
  WHERE parent_ext.value:url::STRING = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity'
  GROUP BY patient_id
),

-- Extract geolocation from address extension
geolocation AS (
  SELECT
    resource:id::STRING as patient_id,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'latitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lat,
    MAX(CASE WHEN geo_ext.value:url::STRING = 'longitude' THEN geo_ext.value:valueDecimal::FLOAT END) as lon
  FROM patient_resources,
  LATERAL FLATTEN(input => resource:address[0]:extension, outer => true) addr_ext,
  LATERAL FLATTEN(input => addr_ext.value:extension, outer => true) geo_ext
  WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
  GROUP BY patient_id
),

flattened AS (
  SELECT
    pr.resource:id::STRING as id,
    TRY_CAST(pr.resource:birthDate::STRING AS DATE) as birthdate,
    TRY_TO_TIMESTAMP(pr.resource:deceasedDateTime::STRING) as deathdate,
    pr.resource:gender::STRING as gender,
    
    -- Identifiers
    i.ssn,
    i.drivers,
    i.passport,
    
    -- Name components
    pr.resource:name[0]:prefix[0]::STRING as prefix,
    pr.resource:name[0]:given[0]::STRING as first,
    pr.resource:name[0]:given[1]::STRING as middle,
    pr.resource:name[0]:family::STRING as last,
    pr.resource:name[0]:suffix[0]::STRING as suffix,
    
    -- Extensions
    e.maiden,
    
    -- Marital status
    pr.resource:maritalStatus:coding[0]:code::STRING as marital,
    
    -- Race and ethnicity
    r.race,
    eth.ethnicity,
    
    -- Birthplace
    e.birthplace,
    
    -- Address
    pr.resource:address[0]:line[0]::STRING as address,
    pr.resource:address[0]:city::STRING as city,
    pr.resource:address[0]:state::STRING as state,
    pr.resource:address[0]:district::STRING as county,
    pr.resource:address[0]:postalCode::STRING as zip,
    
    -- Geolocation
    g.lat,
    g.lon,
    
    -- Placeholder columns (will be calculated in marts)
    NULL as fips,
    0.00 as healthcare_expenses,
    0.00 as healthcare_coverage,
    0 as income,
    
    pr.loaded_at
  FROM patient_resources pr
  LEFT JOIN identifiers i ON pr.resource:id::STRING = i.patient_id
  LEFT JOIN extensions e ON pr.resource:id::STRING = e.patient_id
  LEFT JOIN race_ext r ON pr.resource:id::STRING = r.patient_id
  LEFT JOIN ethnicity_ext eth ON pr.resource:id::STRING = eth.patient_id
  LEFT JOIN geolocation g ON pr.resource:id::STRING = g.patient_id
)

SELECT * FROM flattened
