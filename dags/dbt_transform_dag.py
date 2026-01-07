"""
dbt FHIR Transformation DAG

This DAG orchestrates dbt transformations on FHIR data in Snowflake.
It runs staging, intermediate, and marts models in sequence with testing.

Schedule: Every 10 minutes
Dependencies: Waits for s3_to_snowflake_load DAG to complete
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.operators.python import PythonOperator
import logging
import json
import os

# Default arguments for the DAG
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=2),
}

# DAG Configuration
dag = DAG(
    'dbt_transform_fhir',
    default_args=default_args,
    description='Run dbt transformations on FHIR data',
    schedule_interval='*/10 * * * *',  # Every 10 minutes
    max_active_runs=1,  # Sequential execution only
    catchup=False,
    tags=['dbt', 'transformation', 'fhir', 'analytics'],
)

# dbt project directory
DBT_PROJECT_DIR = '/opt/airflow/dbt'
DBT_PROFILES_DIR = '/opt/airflow/dbt'


def check_dbt_installation(**context):
    """Verify dbt is installed and accessible."""
    import subprocess
    
    try:
        result = subprocess.run(['dbt', '--version'], capture_output=True, text=True, check=True)
        logging.info(f'dbt version: {result.stdout}')
        return 'dbt is installed'
    except subprocess.CalledProcessError as e:
        logging.error(f'dbt not found or error: {e}')
        raise
    except FileNotFoundError:
        logging.error('dbt command not found in PATH')
        raise


def parse_dbt_results(**context):
    """Parse dbt run results and log summary."""
    ti = context['ti']
    task_id = context['params'].get('task_id', 'unknown')
    results_path = os.path.join(DBT_PROJECT_DIR, 'target', 'run_results.json')
    
    if not os.path.exists(results_path):
        logging.warning(f'No run results found at {results_path}')
        return
    
    try:
        with open(results_path, 'r') as f:
            results = json.load(f)
        
        total_models = len(results.get('results', []))
        successful = sum(1 for r in results.get('results', []) if r.get('status') == 'success')
        failed = sum(1 for r in results.get('results', []) if r.get('status') == 'error')
        skipped = sum(1 for r in results.get('results', []) if r.get('status') == 'skipped')
        
        logging.info(f'=== dbt {task_id} Summary ===')
        logging.info(f'Total models: {total_models}')
        logging.info(f'✓ Successful: {successful}')
        if failed > 0:
            logging.error(f'✗ Failed: {failed}')
        if skipped > 0:
            logging.info(f'⊘ Skipped: {skipped}')
        
        if failed > 0:
            logging.error('Failed models:')
            for result in results.get('results', []):
                if result.get('status') == 'error':
                    model_name = result.get('unique_id', 'unknown')
                    error_msg = result.get('message', 'No error message')
                    logging.error(f'  - {model_name}: {error_msg}')
        
        return {'total': total_models, 'successful': successful, 'failed': failed, 'skipped': skipped}
    except Exception as e:
        logging.error(f'Error parsing dbt results: {str(e)}')
        return None


# Task 0: Wait for S3 loader to complete
# Use execution_delta to look for the most recent completed run (within last 15 minutes)
wait_for_s3_load = ExternalTaskSensor(
    task_id='wait_for_s3_load',
    external_dag_id='s3_to_snowflake_load',
    external_task_id='update_watermark',
    allowed_states=['success'],
    failed_states=['failed', 'skipped'],
    mode='reschedule',
    timeout=600,
    poke_interval=60,
    check_existence=True,  # Don't fail if external task doesn't exist yet
    execution_delta=None,  # Don't require exact execution date match
    dag=dag,
)

# Task 1: Check dbt installation
check_dbt = PythonOperator(
    task_id='check_dbt_installation',
    python_callable=check_dbt_installation,
    dag=dag,
)

# Task 2: Install dbt packages
dbt_deps = BashOperator(
    task_id='dbt_deps',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt deps --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Task 3: Test Snowflake connection
dbt_debug = BashOperator(
    task_id='dbt_debug',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt debug --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

# Task 4: Run staging models
dbt_run_staging = BashOperator(
    task_id='dbt_run_staging',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select tag:staging --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

parse_staging_results = PythonOperator(
    task_id='parse_staging_results',
    python_callable=parse_dbt_results,
    params={'task_id': 'staging'},
    dag=dag,
)

# Task 6: Run intermediate models
dbt_run_intermediate = BashOperator(
    task_id='dbt_run_intermediate',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select tag:intermediate --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

parse_intermediate_results = PythonOperator(
    task_id='parse_intermediate_results',
    python_callable=parse_dbt_results,
    params={'task_id': 'intermediate'},
    dag=dag,
)

# Task 8: Run marts models
dbt_run_marts = BashOperator(
    task_id='dbt_run_marts',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt run --select tag:marts --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

parse_marts_results = PythonOperator(
    task_id='parse_marts_results',
    python_callable=parse_dbt_results,
    params={'task_id': 'marts'},
    dag=dag,
)

# Task 10: Run dbt tests
dbt_test = BashOperator(
    task_id='dbt_test',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt test --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
)

parse_test_results = PythonOperator(
    task_id='parse_test_results',
    python_callable=parse_dbt_results,
    params={'task_id': 'test'},
    dag=dag,
)

# Task 12: Generate dbt documentation
dbt_docs_generate = BashOperator(
    task_id='dbt_docs_generate',
    bash_command=f'cd {DBT_PROJECT_DIR} && dbt docs generate --profiles-dir {DBT_PROFILES_DIR}',
    dag=dag,
    trigger_rule='all_done',
)

# Task dependencies
# Removed wait_for_s3_load sensor - dbt runs on schedule and data will be available
# since s3_to_snowflake_load runs every 5 min (more frequent than dbt's 10 min)
check_dbt >> dbt_deps >> dbt_debug
dbt_debug >> dbt_run_staging >> parse_staging_results
parse_staging_results >> dbt_run_intermediate >> parse_intermediate_results
parse_intermediate_results >> dbt_run_marts >> parse_marts_results
parse_marts_results >> dbt_test >> parse_test_results >> dbt_docs_generate
