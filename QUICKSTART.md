# Quick Start Guide: dbt-Airflow Integration

## Prerequisites Checklist

Before starting the pipeline, ensure you have:

- [ ] Snowflake account with credentials configured
- [ ] AWS S3 bucket created and accessible
- [ ] Airflow environment variables set (see below)
- [ ] Docker and docker-compose installed
- [ ] Git repository access

## Step 1: Configure Environment Variables

Create or update `.env` file in the project root:

```bash
# Airflow Core
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow
AIRFLOW_UID=50000

# AWS Credentials
AWS_ACCESS_KEY_ID=<your_aws_access_key>
AWS_SECRET_ACCESS_KEY=<your_aws_secret_key>
AWS_S3_BUCKET=synthea-fhir-data-dump
AWS_S3_PREFIX=raw
AWS_CONN_ID=aws_default
AIRFLOW_CONN_AWS_DEFAULT=aws://<access_key>:<secret_key>@

# Snowflake Credentials
SNOWFLAKE_ACCOUNT=<your_account>.snowflakecomputing.com
SNOWFLAKE_USER=<your_username>
SNOWFLAKE_PASSWORD=<your_password>
SNOWFLAKE_DATABASE=SYNTHEA
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=TRANSFORMER
AIRFLOW_CONN_SNOWFLAKE_DEFAULT=snowflake://<user>:<password>@<account>/SYNTHEA?warehouse=COMPUTE_WH&role=TRANSFORMER

# Feature Flags
ENABLE_TRANSFORMATIONS=false
```

## Step 2: Set Up Snowflake Schema

Connect to Snowflake and run:

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS SYNTHEA;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS SYNTHEA.RAW;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.STAGING;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS SYNTHEA.MARTS;

-- Create warehouse
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH 
    WAREHOUSE_SIZE = 'X-SMALL' 
    AUTO_SUSPEND = 60 
    AUTO_RESUME = TRUE;

-- Create role and grant permissions
CREATE ROLE IF NOT EXISTS TRANSFORMER;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TRANSFORMER;
GRANT ALL ON DATABASE SYNTHEA TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA SYNTHEA.RAW TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA SYNTHEA.STAGING TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA SYNTHEA.INTERMEDIATE TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA SYNTHEA.MARTS TO ROLE TRANSFORMER;

-- Assign role to user
GRANT ROLE TRANSFORMER TO USER <your_username>;
```

## Step 3: Start Airflow Services

```bash
# Navigate to project directory
cd /home/shiva/repos/hapi-server

# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# Expected output:
# - postgres (healthy)
# - airflow-init (exited successfully)
# - airflow-webserver (running on port 8080)
# - airflow-scheduler (running)
```

## Step 4: Access Airflow UI

1. Open browser: http://localhost:8080
2. Login credentials:
   - **Username**: `admin`
   - **Password**: `admin`

## Step 5: Verify DAGs Loaded

In Airflow UI, check for these 4 DAGs:

✓ `synthea_patient_generation` - Every 10 seconds  
✓ `s3_upload_patient_data` - Every 30 seconds  
✓ `s3_to_snowflake_load` - Every 5 minutes [NEW]  
✓ `dbt_transform_fhir` - Every 10 minutes [NEW]

If DAGs don't appear:
```bash
# Check DAG parsing logs
docker-compose logs airflow-scheduler | grep "DAG"

# List DAGs from CLI
docker-compose exec airflow-scheduler airflow dags list
```

## Step 6: Configure Airflow Connections (If Not Using Env Vars)

### Option A: Via Airflow UI
1. Go to **Admin → Connections**
2. Add **AWS Connection**:
   - Conn Id: `aws_default`
   - Conn Type: `Amazon Web Services`
   - AWS Access Key ID: `<your_key>`
   - AWS Secret Access Key: `<your_secret>`

3. Add **Snowflake Connection**:
   - Conn Id: `snowflake_default`
   - Conn Type: `Snowflake`
   - Host: `<account>.snowflakecomputing.com`
   - Schema: `RAW`
   - Login: `<username>`
   - Password: `<password>`
   - Extra: `{"account": "<account>", "warehouse": "COMPUTE_WH", "database": "SYNTHEA", "role": "TRANSFORMER"}`

### Option B: Via CLI
```bash
# AWS connection
docker-compose exec airflow-scheduler airflow connections add \
    'aws_default' \
    --conn-type 'aws' \
    --conn-login '<access_key>' \
    --conn-password '<secret_key>'

# Snowflake connection
docker-compose exec airflow-scheduler airflow connections add \
    'snowflake_default' \
    --conn-type 'snowflake' \
    --conn-host '<account>.snowflakecomputing.com' \
    --conn-login '<username>' \
    --conn-password '<password>' \
    --conn-schema 'RAW' \
    --conn-extra '{"account": "<account>", "warehouse": "COMPUTE_WH", "database": "SYNTHEA", "role": "TRANSFORMER"}'
```

## Step 7: Test dbt Connection

```bash
# Enter Airflow scheduler container
docker-compose exec airflow-scheduler bash

# Test dbt setup
cd /opt/airflow/dbt
dbt debug --profiles-dir /opt/airflow/dbt

# Expected output:
# Connection test: [OK connection ok]
```

If connection fails:
- Verify `dbt/profiles.yml` has correct credentials
- Check Snowflake warehouse is running
- Verify network connectivity to Snowflake

## Step 8: Run Initial Pipeline Test

### Manual Trigger Sequence:

1. **Generate Data** (runs automatically every 10s, or trigger manually):
   - DAG: `synthea_patient_generation`
   - Wait for success (creates files in `output/bundles/`)

2. **Upload to S3**:
   - DAG: `s3_upload_patient_data`
   - Wait for success (uploads to S3, creates `.uploaded` markers)

3. **Load to Snowflake**:
   - DAG: `s3_to_snowflake_load`
   - Wait for success (creates RAW tables, loads JSON)

4. **Run dbt Transformations**:
   - DAG: `dbt_transform_fhir`
   - Wait for success (runs all dbt models + tests)

### Verify Data Flow:

```sql
-- Check RAW layer
SELECT COUNT(*) FROM SYNTHEA.RAW.FHIR_BUNDLES;
-- Should see rows equal to number of uploaded files

-- Check STAGING layer
SELECT COUNT(*) FROM SYNTHEA.STAGING.STG_PATIENTS;
-- Should see patient records

-- Check MARTS layer
SELECT COUNT(*) FROM SYNTHEA.MARTS.DIM_PATIENTS;
SELECT COUNT(*) FROM SYNTHEA.MARTS.FCT_ENCOUNTERS;
-- Should see analytics-ready data
```

## Step 9: Monitor Pipeline Health

### Airflow UI Checks:
- **DAGs View**: All DAGs show green (success)
- **Task Duration**: Check for anomalies
- **Logs**: Review for warnings or errors

### Snowflake Checks:
```sql
-- Check data freshness
SELECT MAX(LOADED_AT) FROM SYNTHEA.RAW.FHIR_BUNDLES;

-- Check watermark progress
SELECT * FROM SYNTHEA.RAW.LOAD_WATERMARK ORDER BY LOAD_ID DESC LIMIT 5;

-- Check row counts by layer
SELECT 'RAW' AS LAYER, COUNT(*) FROM SYNTHEA.RAW.FHIR_BUNDLES
UNION ALL
SELECT 'STAGING', COUNT(*) FROM SYNTHEA.STAGING.STG_PATIENTS
UNION ALL
SELECT 'MARTS', COUNT(*) FROM SYNTHEA.MARTS.DIM_PATIENTS;
```

### System Resource Checks:
```bash
# Check Docker container resources
docker stats

# Check Airflow scheduler logs
docker-compose logs -f airflow-scheduler

# Check for errors
docker-compose logs airflow-scheduler | grep ERROR
```

## Step 10: Enable Scheduled Execution

Once manual tests pass, enable automatic scheduling:

1. In Airflow UI, toggle each DAG to **ON** (unpause)
2. Verify schedules:
   - synthea_patient_generation: Every 10 seconds
   - s3_upload_patient_data: Every 30 seconds
   - s3_to_snowflake_load: Every 5 minutes
   - dbt_transform_fhir: Every 10 minutes

3. Monitor for 30 minutes to ensure stable operation

## Troubleshooting Common Issues

### Issue: DAGs not appearing
```bash
# Restart Airflow services
docker-compose restart airflow-scheduler airflow-webserver

# Clear Python cache
docker-compose exec airflow-scheduler rm -rf /opt/airflow/dags/__pycache__
```

### Issue: "S3 access denied"
- Verify AWS credentials in environment variables
- Check S3 bucket policy allows your IAM user
- Test with AWS CLI: `aws s3 ls s3://<bucket>/`

### Issue: "Snowflake connection failed"
- Verify credentials: account, user, password, warehouse
- Check Snowflake user has correct role assigned
- Test with SnowSQL: `snowsql -a <account> -u <user>`

### Issue: "dbt models failing"
```bash
# Enter container and run dbt manually
docker-compose exec airflow-scheduler bash
cd /opt/airflow/dbt
dbt run --select stg_patients --profiles-dir /opt/airflow/dbt

# Check for SQL errors in output
# Review dbt logs in target/
```

### Issue: "ExternalTaskSensor timeout"
- Check if upstream DAG (s3_to_snowflake_load) completed successfully
- Verify task_id matches exactly: `update_watermark`
- Check sensor timeout settings (default 600 seconds)

## Performance Tuning

### For High Volume (1000+ patients/day):

1. **Adjust Snowflake Warehouse Size**:
```sql
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = 'SMALL';
```

2. **Increase dbt Threads**:
```yaml
# dbt/profiles.yml
threads: 8  # Increase from 4
```

3. **Batch Size Optimization**:
```python
# In s3_to_snowflake_load_dag.py, line ~155
new_files = new_files[:500]  # Increase from 100
```

4. **Parallel DAG Runs**:
```python
# In DAG definitions, change:
max_active_runs=3  # Allow parallel execution
```

## Next Steps

1. Set up monitoring alerts (email/Slack)
2. Create custom metrics dashboard
3. Implement data quality checks
4. Schedule regular backups
5. Document business logic in dbt models
6. Create BI dashboards on MARTS layer

## Support & Resources

- **Airflow Docs**: https://airflow.apache.org/docs/
- **dbt Docs**: https://docs.getdbt.com/
- **Snowflake Docs**: https://docs.snowflake.com/
- **Project Issues**: Check logs in `logs/` directory
- **Integration Guide**: See `DBT_AIRFLOW_INTEGRATION.md`
- **Architecture Docs**: See `PIPELINE_ARCHITECTURE.md`

---

**Last Updated**: January 7, 2026  
**Status**: Ready for Deployment ✓
