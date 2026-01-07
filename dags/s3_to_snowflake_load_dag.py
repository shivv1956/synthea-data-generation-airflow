"""
S3 to Snowflake Loader DAG

This DAG loads FHIR bundle JSON files from S3 into Snowflake's RAW layer.
It uses incremental watermark tracking to avoid reprocessing files.

Schedule: Every 5 minutes
Dependencies: Triggered after s3_upload_patient_data DAG
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
import logging

# Default arguments for the DAG
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=1),
}

# DAG Configuration
dag = DAG(
    's3_to_snowflake_load',
    default_args=default_args,
    description='Load FHIR bundles from S3 to Snowflake RAW layer',
    schedule_interval='*/5 * * * *',  # Every 5 minutes
    max_active_runs=1,  # Prevent concurrent runs
    catchup=False,
    tags=['etl', 'snowflake', 's3', 'fhir'],
)


def create_snowflake_tables(**context):
    """
    Create Snowflake tables if they don't exist:
    - SYNTHEA.RAW.FHIR_BUNDLES: Stores FHIR bundle JSON data
    - SYNTHEA.RAW.LOAD_WATERMARK: Tracks last processed S3 file
    """
    import os
    
    hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    database = os.getenv('SNOWFLAKE_DATABASE', 'SYNTHEA')
    schema = os.getenv('SNOWFLAKE_SCHEMA', 'RAW')
    
    # SQL to create FHIR_BUNDLES table
    create_bundles_table = f"""
    CREATE TABLE IF NOT EXISTS {database}.{schema}.FHIR_BUNDLES (
        FILE_KEY VARCHAR(500) PRIMARY KEY,
        BUNDLE_DATA VARIANT,
        LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
        S3_LAST_MODIFIED TIMESTAMP_LTZ,
        RECORD_COUNT NUMBER
    );
    """
    
    # SQL to create LOAD_WATERMARK table
    create_watermark_table = f"""
    CREATE TABLE IF NOT EXISTS {database}.{schema}.LOAD_WATERMARK (
        LOAD_ID NUMBER AUTOINCREMENT PRIMARY KEY,
        LAST_PROCESSED_KEY VARCHAR(500),
        LAST_PROCESSED_TIME TIMESTAMP_LTZ,
        FILES_PROCESSED NUMBER,
        LOAD_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
    );
    """
    
    try:
        logging.info("Creating Snowflake tables if they don't exist...")
        hook.run(create_bundles_table)
        logging.info(f"✓ {database}.{schema}.FHIR_BUNDLES table ready")
        
        hook.run(create_watermark_table)
        logging.info(f"✓ {database}.{schema}.LOAD_WATERMARK table ready")
        
        return "Tables created successfully"
    except Exception as e:
        logging.error(f"Error creating tables: {str(e)}")
        raise


def get_last_watermark(**context):
    """
    Retrieve the last processed S3 key from the watermark table.
    Returns None if no watermark exists (first run).
    """
    import os
    
    hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    database = os.getenv('SNOWFLAKE_DATABASE', 'SYNTHEA')
    schema = os.getenv('SNOWFLAKE_SCHEMA', 'RAW')
    
    query = f"""
    SELECT LAST_PROCESSED_KEY, LAST_PROCESSED_TIME 
    FROM {database}.{schema}.LOAD_WATERMARK 
    ORDER BY LOAD_ID DESC 
    LIMIT 1;
    """
    
    try:
        result = hook.get_first(query)
        if result:
            last_key, last_time = result
            logging.info(f"Last watermark: {last_key} at {last_time}")
            return last_key
        else:
            logging.info("No watermark found - this is the first load")
            return None
    except Exception as e:
        logging.warning(f"Could not retrieve watermark: {str(e)}")
        return None


def list_new_s3_files(**context):
    """
    List S3 files that haven't been processed yet.
    Returns list of file keys newer than the watermark.
    """
    import os
    
    s3_hook = S3Hook(aws_conn_id='aws_default')
    bucket = os.getenv('AWS_S3_BUCKET', 'synthea-fhir-data-dump')
    prefix = os.getenv('AWS_S3_PREFIX', 'raw') + '/patients/'
    
    # Get last processed key from XCom
    ti = context['ti']
    last_watermark = ti.xcom_pull(task_ids='get_last_watermark')
    
    try:
        # List all objects in the S3 prefix
        all_keys = s3_hook.list_keys(bucket_name=bucket, prefix=prefix)
        
        if not all_keys:
            logging.info("No files found in S3")
            return []
        
        # Filter for FHIR bundle files only (exclude .uploaded markers)
        fhir_files = [key for key in all_keys if key.endswith('.json')]
        
        # If watermark exists, filter for newer files
        if last_watermark:
            # Get file metadata and filter by last modified time
            new_files = []
            for key in fhir_files:
                if key not in last_watermark:  # Simple string comparison for now
                    new_files.append(key)
        else:
            new_files = fhir_files
        
        # Limit to 100 files per batch to avoid overwhelming Snowflake
        new_files = new_files[:100]
        
        logging.info(f"Found {len(new_files)} new files to process")
        return new_files
        
    except Exception as e:
        logging.error(f"Error listing S3 files: {str(e)}")
        raise


def load_files_to_snowflake(**context):
    """
    Load new S3 files into Snowflake using COPY INTO command.
    Uses Snowflake's native S3 integration for efficient bulk loading.
    """
    import os
    
    ti = context['ti']
    new_files = ti.xcom_pull(task_ids='list_new_s3_files')
    
    if not new_files or len(new_files) == 0:
        logging.info("No new files to load - skipping")
        return {"files_loaded": 0}
    
    hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    bucket = os.getenv('AWS_S3_BUCKET', 'synthea-fhir-data-dump')
    prefix = os.getenv('AWS_S3_PREFIX', 'raw')
    database = os.getenv('SNOWFLAKE_DATABASE', 'SYNTHEA')
    schema = os.getenv('SNOWFLAKE_SCHEMA', 'RAW')
    aws_key_id = os.getenv('AWS_ACCESS_KEY_ID', '')
    aws_secret_key = os.getenv('AWS_SECRET_ACCESS_KEY', '')
    
    # Create S3 stage for external access
    create_stage_sql = f"""
    CREATE OR REPLACE STAGE {database}.{schema}.S3_FHIR_STAGE
    URL='s3://{bucket}/{prefix}/patients/'
    CREDENTIALS=(AWS_KEY_ID='{aws_key_id}' AWS_SECRET_KEY='{aws_secret_key}')
    FILE_FORMAT = (TYPE = 'JSON');
    """
    
    # COPY INTO command to load JSON files
    copy_into_sql = f"""
    COPY INTO {database}.{schema}.FHIR_BUNDLES (FILE_KEY, BUNDLE_DATA, S3_LAST_MODIFIED)
    FROM (
        SELECT 
            METADATA$FILENAME as FILE_KEY,
            $1 as BUNDLE_DATA,
            TO_TIMESTAMP_LTZ(METADATA$FILE_LAST_MODIFIED) as S3_LAST_MODIFIED
        FROM @{database}.{schema}.S3_FHIR_STAGE
    )
    PATTERN = '.*\\.json'
    ON_ERROR = 'CONTINUE'
    FORCE = FALSE;
    """
    
    try:
        logging.info(f"Loading {len(new_files)} files from S3 to Snowflake...")
        
        # Create stage (will replace if exists)
        hook.run(create_stage_sql)
        logging.info("✓ S3 stage created")
        
        # Execute COPY INTO
        result = hook.run(copy_into_sql)
        logging.info(f"✓ COPY INTO completed: {result}")
        
        # Count records loaded
        count_query = f"SELECT COUNT(*) FROM {database}.{schema}.FHIR_BUNDLES;"
        total_records = hook.get_first(count_query)[0]
        
        logging.info(f"Total records in FHIR_BUNDLES: {total_records}")
        
        return {
            "files_loaded": len(new_files),
            "total_records": total_records
        }
        
    except Exception as e:
        logging.error(f"Error loading files to Snowflake: {str(e)}")
        raise


def update_watermark(**context):
    """
    Update the watermark table with the latest processed file info.
    """
    import os
    
    ti = context['ti']
    new_files = ti.xcom_pull(task_ids='list_new_s3_files')
    load_result = ti.xcom_pull(task_ids='load_files_to_snowflake')
    
    if not new_files or len(new_files) == 0:
        logging.info("No files processed - skipping watermark update")
        return
    
    hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    database = os.getenv('SNOWFLAKE_DATABASE', 'SYNTHEA')
    schema = os.getenv('SNOWFLAKE_SCHEMA', 'RAW')
    
    # Get the latest file key (assumes sorted)
    last_key = sorted(new_files)[-1]
    files_count = load_result.get('files_loaded', 0)
    
    insert_watermark = f"""
    INSERT INTO {database}.{schema}.LOAD_WATERMARK (LAST_PROCESSED_KEY, LAST_PROCESSED_TIME, FILES_PROCESSED)
    VALUES ('{last_key}', CURRENT_TIMESTAMP(), {files_count});
    """
    
    try:
        hook.run(insert_watermark)
        logging.info(f"✓ Watermark updated: {last_key} ({files_count} files)")
    except Exception as e:
        logging.error(f"Error updating watermark: {str(e)}")
        raise


# Task definitions
task_create_tables = PythonOperator(
    task_id='create_snowflake_tables',
    python_callable=create_snowflake_tables,
    dag=dag,
)

task_get_watermark = PythonOperator(
    task_id='get_last_watermark',
    python_callable=get_last_watermark,
    dag=dag,
)

task_list_files = PythonOperator(
    task_id='list_new_s3_files',
    python_callable=list_new_s3_files,
    dag=dag,
)

task_load_files = PythonOperator(
    task_id='load_files_to_snowflake',
    python_callable=load_files_to_snowflake,
    dag=dag,
)

task_update_watermark = PythonOperator(
    task_id='update_watermark',
    python_callable=update_watermark,
    dag=dag,
)

# Task dependencies
task_create_tables >> task_get_watermark >> task_list_files >> task_load_files >> task_update_watermark
