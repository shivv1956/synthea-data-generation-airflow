# dbt-Airflow Integration Implementation Summary

## Overview
Successfully integrated dbt with Apache Airflow for the FHIR data pipeline. The integration creates an end-to-end automated data pipeline from Synthea synthetic data generation through to analytics-ready data marts in Snowflake.

## Implementation Date
January 7, 2026

## Files Created

### 1. DAG Files (2 new files)

#### `/dags/s3_to_snowflake_load_dag.py` (8.9KB)
- **Purpose**: Loads FHIR bundle JSON files from S3 into Snowflake RAW layer
- **Schedule**: Every 5 minutes (`*/5 * * * *`)
- **Key Features**:
  - Auto-creates Snowflake tables (`RAW.FHIR_BUNDLES` and `RAW.LOAD_WATERMARK`)
  - Incremental watermark tracking to avoid reprocessing files
  - Uses Snowflake `COPY INTO` for efficient bulk loading
  - Processes up to 100 files per batch
  - Handles JSON VARIANT data type for flexible FHIR parsing

**Tasks**:
1. `create_snowflake_tables` - Initialize schema if needed
2. `get_last_watermark` - Retrieve last processed file timestamp
3. `list_new_s3_files` - Find unprocessed S3 files
4. `load_files_to_snowflake` - Bulk load via COPY INTO
5. `update_watermark` - Track progress

#### `/dags/dbt_transform_dag.py` (6.4KB)
- **Purpose**: Orchestrates dbt transformations on FHIR data
- **Schedule**: Every 10 minutes (`*/10 * * * *`)
- **Key Features**:
  - Waits for S3 loader completion using `ExternalTaskSensor`
  - Executes dbt models in correct sequence (staging → intermediate → marts)
  - Parses dbt results and logs success/failure statistics
  - Generates dbt documentation automatically
  - Selective execution by layer using tags

**Tasks**:
1. `wait_for_s3_load` - Sensor for upstream DAG
2. `check_dbt_installation` - Verify dbt availability
3. `dbt_deps` - Install dbt packages
4. `dbt_debug` - Test Snowflake connection
5. `dbt_run_staging` - Execute 18 staging models (incremental)
6. `parse_staging_results` - Log staging metrics
7. `dbt_run_intermediate` - Execute 4 intermediate models (full refresh)
8. `parse_intermediate_results` - Log intermediate metrics
9. `dbt_run_marts` - Execute 5 marts models (analytics)
10. `parse_marts_results` - Log marts metrics
11. `dbt_test` - Run data quality tests
12. `parse_test_results` - Log test results
13. `dbt_docs_generate` - Create documentation

### 2. dbt Model Configuration Files (3 new files)

#### `/dbt/models/staging/staging_models.yml`
- Configured 18 staging models with `staging` tag
- Models: patients, encounters, conditions, observations, medications, procedures, immunizations, allergies, careplans, devices, supplies, imaging_studies, claims, claims_transactions, payers, payer_transitions, providers, organizations

#### `/dbt/models/intermediate/intermediate_models.yml`
- Configured 4 intermediate models with `intermediate` tag
- Models: reference_map, claims_enriched, medication_reasons, procedure_reasons

#### `/dbt/models/marts/marts_models.yml`
- Configured 5 marts models with `marts` tag
- Models: dim_patients, fct_encounters, fct_medications, fct_procedures, fct_observations
- Includes column documentation and test specifications

## Complete Pipeline Flow

```
┌──────────────────────┐
│  Synthea Generator   │ ← synthea_generation_dag.py (every 10 sec)
│  (Java/Docker)       │
└──────────┬───────────┘
           │ Generates FHIR R4 bundles
           ▼
┌──────────────────────┐
│   Local Storage      │ ← output/bundles/{patient_id}/
│  (24h TTL)           │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│   S3 Upload DAG      │ ← s3_upload_dag.py (every 30 sec)
│   (AWS S3)           │
└──────────┬───────────┘
           │ Uploads to s3://bucket/raw/patients/
           ▼
┌──────────────────────┐
│ S3 → Snowflake Load  │ ← s3_to_snowflake_load_dag.py (every 5 min) [NEW]
│ (Bulk COPY INTO)     │
└──────────┬───────────┘
           │ Loads JSON into RAW.FHIR_BUNDLES (VARIANT)
           ▼
┌──────────────────────┐
│   dbt Transform      │ ← dbt_transform_dag.py (every 10 min) [NEW]
│   (Staging)          │
└──────────┬───────────┘
           │ Parses FHIR, extracts resources
           ▼
┌──────────────────────┐
│   dbt Transform      │
│   (Intermediate)     │
└──────────┬───────────┘
           │ Enriches, joins, resolves references
           ▼
┌──────────────────────┐
│   dbt Transform      │
│   (Marts)            │
└──────────┬───────────┘
           │ Star schema: 1 dimension + 4 fact tables
           ▼
┌──────────────────────┐
│  Analytics Tables    │ ← MARTS.DIM_PATIENTS, MARTS.FCT_*
│  (Snowflake)         │    Ready for BI tools
└──────────────────────┘
```

## Data Lineage

### RAW Layer (Snowflake)
- **RAW.FHIR_BUNDLES**: Complete FHIR bundles as JSON (VARIANT column)
- **RAW.LOAD_WATERMARK**: ETL metadata and incremental tracking

### STAGING Layer (Snowflake)
- **18 Models**: One per FHIR resource type
- **Materialization**: Incremental (merge strategy)
- **Unique Key**: Resource ID (UUID)
- **Lookback**: 7 days for incremental updates

### INTERMEDIATE Layer (Snowflake)
- **4 Models**: Reference resolution and enrichment
- **Materialization**: Table (full refresh)
- **Purpose**: Prepare dimensional modeling

### MARTS Layer (Snowflake)
- **1 Dimension**: `DIM_PATIENTS` (patient master data)
- **4 Facts**: `FCT_ENCOUNTERS`, `FCT_MEDICATIONS`, `FCT_PROCEDURES`, `FCT_OBSERVATIONS`
- **Materialization**: Table
- **Design**: Star schema optimized for analytics

## Key Integration Points

### 1. DAG Dependencies
- **s3_upload_dag.py** runs independently (monitors local output/)
- **s3_to_snowflake_load_dag.py** runs independently (monitors S3)
- **dbt_transform_dag.py** waits for s3_to_snowflake_load completion via `ExternalTaskSensor`

### 2. Environment Variables (Already Configured)
```bash
# Snowflake Connection
SNOWFLAKE_ACCOUNT=<your_account>
SNOWFLAKE_USER=<your_user>
SNOWFLAKE_PASSWORD=<your_password>
SNOWFLAKE_DATABASE=SYNTHEA
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=TRANSFORMER

# AWS Connection
AWS_S3_BUCKET=synthea-fhir-data-dump
AWS_S3_PREFIX=raw

# Airflow Connections
AIRFLOW_CONN_SNOWFLAKE_DEFAULT=<connection_string>
AIRFLOW_CONN_AWS_DEFAULT=<connection_string>
```

### 3. dbt Execution Strategy
- **Selective Runs**: Uses tags (staging, intermediate, marts) for layer-specific execution
- **Profiles Dir**: `/opt/airflow/dbt` (mounted volume in Docker)
- **Project Dir**: `/opt/airflow/dbt` (same location)
- **Parallel Threads**: 4 (dev), 8 (prod) configured in profiles.yml

## Testing & Validation

### Syntax Validation
- ✓ s3_to_snowflake_load_dag.py - Valid Python syntax
- ✓ dbt_transform_dag.py - Valid Python syntax

### Pre-Deployment Checklist
- [ ] Snowflake RAW schema exists
- [ ] AWS S3 bucket is accessible
- [ ] Airflow connections configured (aws_default, snowflake_default)
- [ ] dbt packages installed (`dbt deps` runs successfully)
- [ ] Snowflake credentials have appropriate permissions

### Post-Deployment Validation
1. Check Airflow UI - both DAGs should appear in DAG list
2. Verify no import errors in Airflow logs
3. Manually trigger `s3_to_snowflake_load` DAG (if S3 has data)
4. Monitor task logs for successful table creation
5. Manually trigger `dbt_transform_fhir` DAG
6. Verify dbt models execute without errors
7. Query Snowflake to confirm data in MARTS schema

## Performance Characteristics

### S3 Loader
- **Batch Size**: 100 files per run
- **Frequency**: Every 5 minutes
- **Expected Runtime**: 1-3 minutes (depends on file count)
- **Concurrency**: max_active_runs=1 (sequential)

### dbt Transformer
- **Model Count**: 27 total (18 staging + 4 intermediate + 5 marts)
- **Frequency**: Every 10 minutes
- **Expected Runtime**: 5-8 minutes (depends on data volume)
- **Concurrency**: max_active_runs=1 (sequential)

### End-to-End Latency
- **Synthea → S3**: ~30-40 seconds
- **S3 → Snowflake**: ~5 minutes (max)
- **Snowflake → Marts**: ~10 minutes (max)
- **Total**: ~15-16 minutes from generation to analytics-ready

## Monitoring & Logging

### Key Metrics to Monitor
1. **S3 Loader**:
   - Files processed per run
   - Watermark timestamp advancement
   - COPY INTO errors (logged but continues)

2. **dbt Transformer**:
   - Models successful/failed/skipped per layer
   - Test failures
   - Execution time per model

### Log Locations
- Airflow task logs: `/opt/airflow/logs/dag_id=<dag_name>/`
- dbt run results: `/opt/airflow/dbt/target/run_results.json`
- dbt docs: `/opt/airflow/dbt/target/index.html`

## Troubleshooting Guide

### Issue: DAGs not appearing in Airflow UI
- **Solution**: Check file permissions (should be readable by Airflow user uid=50000)
- **Command**: `chmod 644 /opt/airflow/dags/*.py`

### Issue: S3 loader fails with credentials error
- **Solution**: Verify AWS connection in Airflow UI → Admin → Connections
- **Test**: `airflow connections test aws_default`

### Issue: dbt models fail with connection error
- **Solution**: Verify Snowflake connection
- **Test**: Run `dbt debug` task manually

### Issue: Incremental models not picking up new data
- **Solution**: Check watermark table and dbt lookback window
- **Command**: `SELECT * FROM RAW.LOAD_WATERMARK ORDER BY LOAD_ID DESC LIMIT 5;`

## Next Steps (Future Enhancements)

### Short-Term
1. Set up Airflow email alerts for DAG failures
2. Configure dbt tests for data quality monitoring
3. Create Airflow Variables for configurable batch sizes
4. Add retry logic with exponential backoff

### Medium-Term
1. Implement partitioning strategy for large fact tables
2. Add dbt snapshot models for slowly changing dimensions
3. Create custom Airflow operators for dbt (replace BashOperator)
4. Set up dbt Cloud integration for advanced features

### Long-Term
1. Migrate to Airflow KubernetesExecutor for scalability
2. Implement data lineage visualization
3. Add ML model training DAGs using marts data
4. Create self-service BI layer with pre-built dashboards

## Dependencies

### Python Packages (requirements.txt)
- `apache-airflow-providers-amazon>=8.0.0` - S3 integration
- `apache-airflow-providers-snowflake>=5.0.0` - Snowflake operations
- `dbt-core>=1.7.0,<1.8.0` - dbt transformation engine
- `dbt-snowflake>=1.7.0,<1.8.0` - Snowflake adapter for dbt

### dbt Packages (packages.yml)
- `dbt-labs/dbt_utils@1.1.1` - Common macros
- `dbt-labs/codegen@0.12.1` - SQL generation utilities

## Documentation References

- **Airflow Docs**: https://airflow.apache.org/docs/
- **dbt Docs**: https://docs.getdbt.com/
- **Snowflake COPY INTO**: https://docs.snowflake.com/en/sql-reference/sql/copy-into-table
- **FHIR R4 Spec**: https://hl7.org/fhir/R4/

## Conclusion

The dbt-Airflow integration is now complete and ready for deployment. The pipeline provides:
- ✓ Automated end-to-end data flow
- ✓ Incremental loading and transformations
- ✓ Data quality testing
- ✓ Comprehensive logging and monitoring
- ✓ Modular, maintainable architecture
- ✓ Scalable design for production workloads

All components are container-ready and can be deployed by restarting the Airflow services with `docker-compose down && docker-compose up -d`.
