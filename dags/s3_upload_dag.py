"""
S3 Upload DAG for Synthea Patient Data
"""
import json, logging, os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List
from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.utils.trigger_rule import TriggerRule

logger = logging.getLogger(__name__)
BUNDLE_STORAGE_DIR = Path("/opt/airflow/output/bundles")
AWS_S3_BUCKET = os.getenv("AWS_S3_BUCKET", "synthea-fhir-data-dump")
AWS_S3_PREFIX = os.getenv("AWS_S3_PREFIX", "raw")
AWS_CONN_ID = os.getenv("AWS_CONN_ID", "aws_default")
ENABLE_TRANSFORMATIONS = os.getenv("ENABLE_TRANSFORMATIONS", "false").lower() == "true"
UPLOAD_MARKER = ".uploaded"

def scan_for_new_patients(**context):
    if not BUNDLE_STORAGE_DIR.exists():
        return []
    new_folders = []
    for patient_dir in BUNDLE_STORAGE_DIR.iterdir():
        if not patient_dir.is_dir() or (patient_dir / UPLOAD_MARKER).exists():
            continue
        if list(patient_dir.glob("*.json")):
            new_folders.append(patient_dir.name)
    context["task_instance"].xcom_push(key="new_patient_folders", value=new_folders)
    return new_folders

def decide_transformation_branch(**context):
    return "transform_data" if ENABLE_TRANSFORMATIONS else "upload_to_s3"

def transform_data(**context):
    new_folders = context["task_instance"].xcom_pull(task_ids="scan_for_new_patients", key="new_patient_folders")
    if not new_folders:
        return {"transformed_count": 0}
    for folder_name in new_folders:
        for json_file in (BUNDLE_STORAGE_DIR / folder_name).glob("*.json"):
            with json_file.open("r") as f:
                json.load(f)
    return {"transformed_count": len(new_folders)}

def upload_to_s3(**context):
    new_folders = context["task_instance"].xcom_pull(task_ids="scan_for_new_patients", key="new_patient_folders")
    if not new_folders:
        return {"uploaded_folders": 0, "uploaded_files": 0}
    s3_hook = S3Hook(aws_conn_id=AWS_CONN_ID)
    uploaded_folders, uploaded_files = 0, 0
    for folder_name in new_folders:
        for json_file in (BUNDLE_STORAGE_DIR / folder_name).glob("*.json"):
            s3_key = f"{AWS_S3_PREFIX}/patients/{folder_name}/{json_file.name}"
            s3_hook.load_file(str(json_file), s3_key, AWS_S3_BUCKET, replace=True)
            uploaded_files += 1
        uploaded_folders += 1
    context["task_instance"].xcom_push(key="uploaded_folders", value=new_folders)
    return {"uploaded_folders": uploaded_folders, "uploaded_files": uploaded_files}

def mark_as_uploaded(**context):
    uploaded_folders = context["task_instance"].xcom_pull(task_ids="upload_to_s3", key="uploaded_folders")
    if not uploaded_folders:
        return {"marked_count": 0}
    marked_count = 0
    for folder_name in uploaded_folders:
        marker_file = BUNDLE_STORAGE_DIR / folder_name / UPLOAD_MARKER
        with marker_file.open("w") as f:
            json.dump({"uploaded_at": datetime.now().isoformat(), "s3_bucket": AWS_S3_BUCKET}, f)
        marked_count += 1
    return {"marked_count": marked_count}

with DAG(
    "s3_upload_patient_data",
    default_args={"owner": "airflow", "retries": 2, "retry_delay": timedelta(seconds=30)},
    description="Upload Synthea patient data to AWS S3",
    schedule_interval="*/30 * * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=3,
    tags=["s3", "upload", "fhir", "aws"],
) as dag:
    scan = PythonOperator(task_id="scan_for_new_patients", python_callable=scan_for_new_patients)
    branch = BranchPythonOperator(task_id="decide_transformation_branch", python_callable=decide_transformation_branch)
    transform = PythonOperator(task_id="transform_data", python_callable=transform_data)
    upload = PythonOperator(task_id="upload_to_s3", python_callable=upload_to_s3, trigger_rule=TriggerRule.NONE_FAILED)
    mark = PythonOperator(task_id="mark_as_uploaded", python_callable=mark_as_uploaded, trigger_rule=TriggerRule.ALL_DONE)
    scan >> branch >> [transform, upload]
    transform >> upload >> mark
    upload >> mark
