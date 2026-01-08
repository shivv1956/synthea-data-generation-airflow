{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'organization']
  )
}}

/*
Marts Model: Organization Dimension
Hospital / clinic / healthcare facility dimension
*/

SELECT
  id as organization_id,
  name,
  address,
  city,
  state,
  zip,
  lat as latitude,
  lon as longitude,
  phone,
  loaded_at as last_updated_at
FROM {{ ref('stg_organizations') }}
