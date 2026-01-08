{{
  config(
    materialized='table',
    tags=['marts', 'dimension', 'date']
  )
}}

/*
Marts Model: Date Dimension
Shared calendar dimension for all fact tables
Generates dates from 2000-01-01 to 2030-12-31
*/

WITH date_spine AS (
  {{ dbt_utils.date_spine(
      datepart="day",
      start_date="cast('2000-01-01' as date)",
      end_date="cast('2030-12-31' as date)"
   )
  }}
),

date_dimension AS (
  SELECT
    date_day as date,
    TO_NUMBER(TO_CHAR(date_day, 'YYYYMMDD')) as date_key,
    YEAR(date_day) as year,
    QUARTER(date_day) as quarter,
    MONTH(date_day) as month,
    TO_CHAR(date_day, 'MMMM') as month_name,
    WEEKOFYEAR(date_day) as week,
    DAY(date_day) as day,
    DAYOFWEEK(date_day) as day_of_week,
    TO_CHAR(date_day, 'DY') as day_name,
    CASE WHEN DAYOFWEEK(date_day) IN (0, 6) THEN TRUE ELSE FALSE END as is_weekend,
    CASE WHEN MONTH(date_day) IN (1,2,3) THEN 'Q1'
         WHEN MONTH(date_day) IN (4,5,6) THEN 'Q2'
         WHEN MONTH(date_day) IN (7,8,9) THEN 'Q3'
         ELSE 'Q4'
    END as quarter_name
  FROM date_spine
)

SELECT * FROM date_dimension
