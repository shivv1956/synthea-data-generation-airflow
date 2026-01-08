{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'provider']
  )
}}

/*
Marts Model: Provider Dimension
Clinician / practitioner master dimension
*/

SELECT
  id as provider_id,
  name,
  gender,
  speciality,
  organization as organization_id,
  address,
  city,
  state,
  zip,
  lat as latitude,
  lon as longitude,
  loaded_at as last_updated_at
FROM {{ ref('stg_providers') }}
