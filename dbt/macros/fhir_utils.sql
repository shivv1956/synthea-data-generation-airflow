{# 
FHIR Utility Macros for DBT Models
Reusable Jinja macros for extracting data from FHIR R4 JSON bundles in Snowflake
#}

{# 
Extract UUID from FHIR reference string
Input: "urn:uuid:12345678-1234-1234-1234-123456789abc" or "Patient/12345678"
Output: "12345678-1234-1234-1234-123456789abc"
#}
{% macro extract_uuid_from_reference(reference_field) %}
  CASE
    WHEN {{ reference_field }}::STRING LIKE 'urn:uuid:%' 
      THEN REPLACE({{ reference_field }}::STRING, 'urn:uuid:', '')
    WHEN {{ reference_field }}::STRING LIKE '%/%'
      THEN SPLIT_PART({{ reference_field }}::STRING, '/', 2)
    ELSE {{ reference_field }}::STRING
  END
{% endmacro %}

{# 
Parse FHIR coding array and extract code, system, and display
Returns the first coding element from a coding array
#}
{% macro parse_fhir_coding(coding_array, field='code') %}
  {% if field == 'code' %}
    {{ coding_array }}[0]:code::STRING
  {% elif field == 'system' %}
    {{ coding_array }}[0]:system::STRING
  {% elif field == 'display' %}
    {{ coding_array }}[0]:display::STRING
  {% else %}
    {{ coding_array }}[0]:{{ field }}::STRING
  {% endif %}
{% endmacro %}

{# 
Extract value from FHIR extension by URL
Handles nested extension structures common in US Core profiles
#}
{% macro extract_extension_value(extension_array, url, value_type='valueString') %}
  (
    SELECT ext.value:{{ value_type }}::STRING
    FROM LATERAL FLATTEN(input => {{ extension_array }}) ext
    WHERE ext.value:url::STRING = '{{ url }}'
    LIMIT 1
  )
{% endmacro %}

{#
Extract nested extension value (for race, ethnicity with text sub-extension)
#}
{% macro extract_nested_extension(extension_array, parent_url, child_url='text', value_type='valueString') %}
  (
    SELECT child_ext.value:{{ value_type }}::STRING
    FROM LATERAL FLATTEN(input => {{ extension_array }}) parent_ext,
         LATERAL FLATTEN(input => parent_ext.value:extension) child_ext
    WHERE parent_ext.value:url::STRING = '{{ parent_url }}'
      AND child_ext.value:url::STRING = '{{ child_url }}'
    LIMIT 1
  )
{% endmacro %}

{# 
Convert FHIR date/datetime to standard format
Handles both YYYY-MM-DD and ISO8601 formats
#}
{% macro safe_date_format(date_field, format='YYYY-MM-DD') %}
  TRY_TO_DATE({{ date_field }}::STRING, 'YYYY-MM-DD')
{% endmacro %}

{% macro safe_timestamp_format(timestamp_field) %}
  TRY_TO_TIMESTAMP({{ timestamp_field }}::STRING)
{% endmacro %}

{#
Coalesce FHIR value that might be in different formats
Handles valueQuantity, valueCodeableConcept, valueString, etc.
#}
{% macro coalesce_fhir_value(value_field) %}
  COALESCE(
    {{ value_field }}:valueQuantity:value::STRING,
    {{ value_field }}:valueCodeableConcept:coding[0]:display::STRING,
    {{ value_field }}:valueCodeableConcept:text::STRING,
    {{ value_field }}:valueString::STRING,
    {{ value_field }}:valueBoolean::STRING,
    {{ value_field }}:valueInteger::STRING,
    {{ value_field }}:valueDecimal::STRING,
    {{ value_field }}:valueDateTime::STRING
  )
{% endmacro %}

{#
Extract patient demographics with all extensions
Handles complex nested structures for race, ethnicity, birthplace, geolocation
#}
{% macro extract_patient_demographics(resource_field) %}
  -- Basic demographics
  {{ resource_field }}:id::STRING as id,
  {{ safe_date_format(resource_field ~ ':birthDate') }} as birth_date,
  {{ safe_timestamp_format(resource_field ~ ':deceasedDateTime') }} as death_date,
  {{ resource_field }}:gender::STRING as gender,
  
  -- Identifiers
  (
    SELECT id_elem.value:value::STRING
    FROM LATERAL FLATTEN(input => {{ resource_field }}:identifier) id_elem
    WHERE id_elem.value:type:coding[0]:code::STRING = 'SS'
    LIMIT 1
  ) as ssn,
  
  (
    SELECT id_elem.value:value::STRING
    FROM LATERAL FLATTEN(input => {{ resource_field }}:identifier) id_elem
    WHERE id_elem.value:type:coding[0]:code::STRING = 'DL'
    LIMIT 1
  ) as drivers_license,
  
  (
    SELECT id_elem.value:value::STRING
    FROM LATERAL FLATTEN(input => {{ resource_field }}:identifier) id_elem
    WHERE id_elem.value:type:coding[0]:code::STRING = 'PPN'
    LIMIT 1
  ) as passport,
  
  -- Name components
  {{ resource_field }}:name[0]:prefix[0]::STRING as prefix,
  {{ resource_field }}:name[0]:given[0]::STRING as first_name,
  {{ resource_field }}:name[0]:given[1]::STRING as middle_name,
  {{ resource_field }}:name[0]:family::STRING as last_name,
  {{ resource_field }}:name[0]:suffix[0]::STRING as suffix,
  
  -- Extensions
  {{ extract_extension_value(resource_field ~ ':extension', 'http://hl7.org/fhir/StructureDefinition/patient-mothersMaidenName', 'valueString') }} as maiden_name,
  {{ extract_nested_extension(resource_field ~ ':extension', 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race', 'text', 'valueString') }} as race,
  {{ extract_nested_extension(resource_field ~ ':extension', 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity', 'text', 'valueString') }} as ethnicity,
  {{ resource_field }}:extension[0]:valueAddress:city::STRING as birthplace,
  
  -- Marital status
  {{ resource_field }}:maritalStatus:coding[0]:code::STRING as marital_status,
  
  -- Address
  {{ resource_field }}:address[0]:line[0]::STRING as address,
  {{ resource_field }}:address[0]:city::STRING as city,
  {{ resource_field }}:address[0]:state::STRING as state,
  {{ resource_field }}:address[0]:postalCode::STRING as zip,
  
  -- Geolocation from address extension
  (
    SELECT geo_ext.value:valueDecimal::FLOAT
    FROM LATERAL FLATTEN(input => {{ resource_field }}:address[0]:extension) addr_ext,
         LATERAL FLATTEN(input => addr_ext.value:extension) geo_ext
    WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
      AND geo_ext.value:url::STRING = 'latitude'
    LIMIT 1
  ) as latitude,
  
  (
    SELECT geo_ext.value:valueDecimal::FLOAT
    FROM LATERAL FLATTEN(input => {{ resource_field }}:address[0]:extension) addr_ext,
         LATERAL FLATTEN(input => addr_ext.value:extension) geo_ext
    WHERE addr_ext.value:url::STRING = 'http://hl7.org/fhir/StructureDefinition/geolocation'
      AND geo_ext.value:url::STRING = 'longitude'
    LIMIT 1
  ) as longitude
{% endmacro %}

{#
Extract code from CodeableConcept
Handles cases where coding might be missing
#}
{% macro extract_codeable_concept(field, component='code') %}
  {% if component == 'code' %}
    COALESCE(
      {{ field }}:coding[0]:code::STRING,
      {{ field }}:text::STRING
    )
  {% elif component == 'system' %}
    {{ field }}:coding[0]:system::STRING
  {% elif component == 'display' %}
    COALESCE(
      {{ field }}:coding[0]:display::STRING,
      {{ field }}:text::STRING
    )
  {% endif %}
{% endmacro %}

{#
Generate incremental filter for staging models
Filters based on loaded_at timestamp for efficient incremental processing
#}
{% macro incremental_filter(timestamp_field='loaded_at') %}
  {% if is_incremental() %}
    WHERE {{ timestamp_field }} > (SELECT MAX({{ timestamp_field }}) FROM {{ this }})
  {% endif %}
{% endmacro %}

{#
Extract quantity value and unit from Observation
#}
{% macro extract_observation_value(value_field) %}
  CASE
    WHEN {{ value_field }}:valueQuantity:value IS NOT NULL 
      THEN {{ value_field }}:valueQuantity:value::STRING
    WHEN {{ value_field }}:valueCodeableConcept IS NOT NULL
      THEN {{ extract_codeable_concept(value_field ~ ':valueCodeableConcept', 'display') }}
    WHEN {{ value_field }}:valueString IS NOT NULL
      THEN {{ value_field }}:valueString::STRING
    ELSE NULL
  END
{% endmacro %}

{% macro extract_observation_unit(value_field) %}
  {{ value_field }}:valueQuantity:unit::STRING
{% endmacro %}

{#
Determine observation value type
#}
{% macro observation_value_type(value_field) %}
  CASE
    WHEN {{ value_field }}:valueQuantity IS NOT NULL THEN 'numeric'
    ELSE 'text'
  END
{% endmacro %}

{#
Extract period start and end dates
#}
{% macro extract_period(period_field) %}
  {{ safe_timestamp_format(period_field ~ ':start') }} as period_start,
  {{ safe_timestamp_format(period_field ~ ':end') }} as period_end
{% endmacro %}

{#
Null-safe boolean conversion
#}
{% macro safe_boolean(field) %}
  COALESCE({{ field }}::BOOLEAN, FALSE)
{% endmacro %}

{#
Generate surrogate key from multiple fields
#}
{% macro generate_surrogate_key(fields) %}
  MD5(CONCAT(
    {% for field in fields %}
      COALESCE({{ field }}::STRING, '')
      {% if not loop.last %}, '|', {% endif %}
    {% endfor %}
  ))
{% endmacro %}
