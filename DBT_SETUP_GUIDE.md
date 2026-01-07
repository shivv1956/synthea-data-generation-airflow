# DBT + Snowflake Integration for FHIR Data Transformation

## Overview

Complete DBT integration added to transform raw FHIR JSON bundles from S3 into normalized Snowflake analytics tables. The pipeline implements a modern ELT architecture with incremental loading and full data quality testing.

## Architecture

```
┌─────────────┐    ┌─────────┐    ┌──────────┐    ┌─────────────┐    ┌─────────────┐
│   Synthea   │───▶│  Local  │───▶│ S3 Raw   │───▶│  Snowflake  │───▶│ DBT Models  │
│  Generator  │    │ Bundles │    │  Layer   │    │   RAW       │    │  STAGING    │
└─────────────┘    └─────────┘    └──────────┘    └─────────────┘    │  ↓          │
     (10s)           (24h TTL)      (permanent)     (5 min load)      │INTERMEDIATE │
                                                                       │  ↓          │
                                                                       │  MARTS      │
                                                                       └─────────────┘
                                                                         (10 min DBT)
```

## What Was Implemented

### 1. **Infrastructure Setup**
- ✅ Added DBT dependencies to [requirements.txt](requirements.txt)
- ✅ Configured Snowflake credentials in [.env](.env)
- ✅ Updated [docker-compose.yml](docker-compose.yml) with Snowflake environment variables
- ✅ Mounted `./dbt` directory for DBT project files

### 2. **S3 to Snowflake Loading DAG**
- **File**: [dags/s3_to_snowflake_load_dag.py](dags/s3_to_snowflake_load_dag.py)
- **Schedule**: Every 5 minutes
- **Features**:
  - Incremental watermark tracking
  - Automatic schema/table creation
  - Batch loading (max 100 files per run)
  - JSON parsing into VARIANT column
  - Error handling and logging

### 3. **DBT Project Structure**
```
dbt/
├── dbt_project.yml          # Project configuration
├── profiles.yml             # Snowflake connection
├── packages.yml             # dbt-utils, codegen
├── models/
│   ├── sources.yml          # Raw source definitions
│   ├── staging/             # 18 incremental staging models
│   │   ├── stg_patients.sql
│   │   ├── stg_encounters.sql
│   │   ├── stg_conditions.sql
│   │   ├── stg_observations.sql
│   │   ├── stg_medications.sql
│   │   ├── stg_procedures.sql
│   │   ├── stg_immunizations.sql
│   │   ├── stg_allergies.sql
│   │   ├── stg_careplans.sql
│   │   ├── stg_devices.sql
│   │   ├── stg_supplies.sql
│   │   ├── stg_imaging_studies.sql
│   │   ├── stg_claims.sql
│   │   ├── stg_claims_transactions.sql
│   │   ├── stg_payers.sql
│   │   ├── stg_payer_transitions.sql
│   │   ├── stg_providers.sql
│   │   └── stg_organizations.sql
│   ├── intermediate/        # 4 full-refresh intermediate models
│   │   ├── int_reference_map.sql
│   │   ├── int_claims_enriched.sql
│   │   ├── int_medication_reasons.sql
│   │   └── int_procedure_reasons.sql
│   └── marts/               # 5 analytics models
│       ├── dim_patients.sql
│       ├── fct_encounters.sql
│       ├── fct_medications.sql
│       ├── fct_procedures.sql
│       └── fct_observations.sql
├── macros/
│   └── fhir_utils.sql       # Reusable FHIR parsing macros
└── tests/                   # Data quality tests
```

### 4. **DBT Transformation DAG**
- **File**: [dags/dbt_transform_dag.py](dags/dbt_transform_dag.py)
- **Schedule**: Every 10 minutes
- **Tasks**:
  1. Check DBT installation
  2. Install DBT packages (`dbt deps`)
  3. Verify Snowflake connection (`dbt debug`)
  4. Run staging models (incremental)
  5. Run intermediate models (full refresh)
  6. Run marts models
  7. Run data quality tests
  8. Generate documentation
  9. Log run results

## Configuration

### Step 1: Update Snowflake Credentials

Edit [.env](.env) with your Snowflake account details:

```bash
SNOWFLAKE_ACCOUNT=your-account.region        # e.g., ab12345.us-east-1
SNOWFLAKE_USER=airflow_user
SNOWFLAKE_PASSWORD=your-secure-password
SNOWFLAKE_DATABASE=SYNTHEA
SNOWFLAKE_WAREHOUSE=COMPUTE_WH              # Start with X-Small
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=TRANSFORMER

# Uncomment and configure the connection string:
AIRFLOW_CONN_SNOWFLAKE_DEFAULT=snowflake://airflow_user:your-password@your-account.region/SYNTHEA/RAW?warehouse=COMPUTE_WH&role=TRANSFORMER
```

### Step 2: Create Snowflake Database and Warehouse

Run in Snowflake:

```sql
-- Create warehouse
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WITH WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

-- Create database
CREATE DATABASE IF NOT EXISTS SYNTHEA;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS SYNTHEA.RAW;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.STAGING;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.MARTS;

-- Create role and grant permissions
CREATE ROLE IF NOT EXISTS TRANSFORMER;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TRANSFORMER;
GRANT ALL ON DATABASE SYNTHEA TO ROLE TRANSFORMER;
GRANT ALL ON ALL SCHEMAS IN DATABASE SYNTHEA TO ROLE TRANSFORMER;
GRANT ROLE TRANSFORMER TO USER airflow_user;
```

### Step 3: Rebuild Docker Containers

```bash
# Stop existing containers
./stop.sh

# Rebuild with new dependencies
docker-compose build

# Start services
./start.sh
```

### Step 4: Verify Installation

1. **Check Airflow UI**: http://localhost:8080 (admin/admin)
2. **Verify DAGs are loaded**:
   - `synthea_patient_generation` (every 10 seconds)
   - `s3_upload_patient_data` (every 30 seconds)
   - `s3_to_snowflake_load` (every 5 minutes) ✨ NEW
   - `dbt_transform_fhir` (every 10 minutes) ✨ NEW

3. **Manually trigger the pipeline**:
   - Trigger `synthea_patient_generation` → generates data
   - Wait for `s3_upload_patient_data` → uploads to S3
   - Trigger `s3_to_snowflake_load` → loads to Snowflake
   - Trigger `dbt_transform_fhir` → transforms data

## Data Models

### Staging Layer (Incremental)
Extracts and flattens FHIR resources from nested JSON:
- **stg_patients**: Demographics with extensions (race, ethnicity, geolocation)
- **stg_encounters**: Visit/encounter data
- **stg_conditions**: Diagnoses and conditions
- **stg_observations**: Lab results, vital signs
- **stg_medications**: Prescription data
- **stg_procedures**: Medical procedures
- **stg_immunizations**: Vaccination records
- **stg_allergies**: Allergy/intolerance data
- **stg_careplans**: Care management plans
- **stg_devices**: Medical devices
- **stg_supplies**: Medical supplies
- **stg_imaging_studies**: Radiology/imaging
- **stg_claims**: Insurance claims (simplified)
- **stg_claims_transactions**: Claim line items
- **stg_payers**: Insurance companies
- **stg_payer_transitions**: Coverage history
- **stg_providers**: Healthcare providers
- **stg_organizations**: Healthcare facilities

### Intermediate Layer (Full Refresh)
Resolves references and enriches data:
- **int_reference_map**: UUID to resource lookup table
- **int_claims_enriched**: Financial data aggregation
- **int_medication_reasons**: Links medications to conditions
- **int_procedure_reasons**: Links procedures to conditions

### Marts Layer (Analytics-Ready)
Denormalized tables for BI tools:
- **dim_patients**: Patient dimension with calculated age, expenses
- **fct_encounters**: Complete encounter/visit facts
- **fct_medications**: Prescription facts with costs
- **fct_procedures**: Procedure facts with costs
- **fct_observations**: Lab results and vital signs

## FHIR Parsing Macros

Reusable Jinja macros in [dbt/macros/fhir_utils.sql](dbt/macros/fhir_utils.sql):
- `extract_uuid_from_reference()`: Parse FHIR references
- `parse_fhir_coding()`: Extract code/system/display
- `extract_extension_value()`: Navigate FHIR extensions
- `extract_nested_extension()`: Handle US Core extensions
- `safe_date_format()`: Convert ISO8601 dates
- `coalesce_fhir_value()`: Handle multiple value types
- `extract_patient_demographics()`: Complete patient extraction
- `extract_codeable_concept()`: CodeableConcept parsing
- `generate_surrogate_key()`: Create composite keys

## Running DBT Manually

```bash
# Enter Airflow container
docker exec -it hapi-server-airflow-webserver-1 bash

# Navigate to DBT project
cd /opt/airflow/dbt

# Install packages
dbt deps --profiles-dir .

# Test connection
dbt debug --profiles-dir .

# Run specific models
dbt run --select stg_patients --profiles-dir .
dbt run --select tag:staging --profiles-dir .
dbt run --select tag:intermediate --full-refresh --profiles-dir .
dbt run --select tag:marts --profiles-dir .

# Run tests
dbt test --profiles-dir .

# Generate documentation
dbt docs generate --profiles-dir .
```

## Monitoring and Troubleshooting

### Check DAG Logs
1. Go to Airflow UI: http://localhost:8080
2. Click on DAG name
3. Click on task instance
4. View logs

### Common Issues

**Issue**: `dbt: command not found`
- **Solution**: Rebuild containers with `docker-compose build`

**Issue**: Snowflake connection failed
- **Solution**: 
  - Verify credentials in `.env`
  - Check Snowflake account is active
  - Ensure warehouse is running
  - Test with `dbt debug`

**Issue**: Staging models have no data
- **Solution**: 
  - Ensure S3 to Snowflake DAG ran successfully
  - Check `RAW.FHIR_BUNDLES` table has data
  - Verify incremental logic with `dbt run --full-refresh`

**Issue**: Claims data incomplete
- **Solution**: Claims/financial data in FHIR is complex; current models provide baseline, can be enhanced based on specific FHIR bundle structure

### View Snowflake Data

```sql
-- Check raw data
SELECT COUNT(*) FROM SYNTHEA.RAW.FHIR_BUNDLES;

-- Check staging data
SELECT COUNT(*) FROM SYNTHEA.STAGING.STG_PATIENTS;
SELECT COUNT(*) FROM SYNTHEA.STAGING.STG_ENCOUNTERS;

-- Check marts data
SELECT * FROM SYNTHEA.MARTS.DIM_PATIENTS LIMIT 10;
SELECT * FROM SYNTHEA.MARTS.FCT_ENCOUNTERS LIMIT 10;
```

## Performance Tuning

### Warehouse Sizing
- **X-Small**: Development, <10 patients/min
- **Small**: Testing, 10-50 patients/min
- **Medium**: Production, 50-200 patients/min

### Incremental Strategy
- Staging models: `merge` strategy with `loaded_at` filter
- Intermediate models: Full refresh to ensure reference integrity
- Marts models: Table materialization for fast queries

### Optimization Tips
1. Add clustering keys in production:
   ```sql
   ALTER TABLE STAGING.STG_ENCOUNTERS CLUSTER BY (patient);
   ```
2. Enable result caching in Snowflake
3. Adjust DBT DAG schedule based on data volume
4. Monitor query performance in Snowflake Query History

## Next Steps

1. **Add Data Quality Tests**:
   - Create custom tests in `dbt/tests/`
   - Add schema tests in model YAMLfiles
   - Implement assertions for business rules

2. **Enhance Claims Models**:
   - Add more sophisticated financial calculations
   - Create payer-specific aggregations
   - Build cost trend analysis

3. **Create Additional Marts**:
   - Patient cohort analysis
   - Provider performance metrics
   - Cost per encounter type
   - Disease prevalence dashboards

4. **Connect BI Tools**:
   - Tableau/PowerBI → Snowflake MARTS schema
   - Build pre-aggregated summary tables
   - Create materialized views for dashboards

5. **Production Readiness**:
   - Set up dbt Cloud or CI/CD pipeline
   - Implement dbt snapshots for SCD Type 2
   - Add monitoring and alerting
   - Document data lineage

## Resources

- [Synthea CSV Data Dictionary](https://github.com/synthetichealth/synthea/wiki/CSV-File-Data-Dictionary)
- [FHIR R4 Specification](https://hl7.org/fhir/R4/)
- [DBT Documentation](https://docs.getdbt.com/)
- [Snowflake Docs](https://docs.snowflake.com/)

## Support

For issues or questions:
1. Check Airflow logs in UI
2. Review DBT run results
3. Inspect Snowflake Query History
4. Verify environment variables in `.env`
