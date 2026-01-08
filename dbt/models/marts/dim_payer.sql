{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'payer']
  )
}}

/*
Marts Model: Payer Dimension
Insurance payer / coverage dimension
*/

SELECT
  id as payer_id,
  name,
  ownership,
  address,
  city,
  state_headquartered as state,
  zip,
  phone,
  loaded_at as last_updated_at
FROM {{ ref('stg_payers') }}
