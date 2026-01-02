"""
Synthea Patient Data Generation DAG for Apache Airflow

This DAG generates synthetic patient data using Synthea every 10 seconds.
Generated FHIR R4 bundles are stored locally and automatically cleaned up after 24 hours.

DAG Configuration:
- Schedule: Every 10 seconds (*/10 * * * *)
- Max Active Runs: 1 (sequential execution prevents overlapping)
- Catchup: False (don't backfill historical runs)
- Retries: 2 attempts with 30-second delays

Tasks:
1. generate_patient: Executes Synthea JAR to create synthetic patient data
2. extract_and_store_bundle: Extracts FHIR bundle and saves to organized directory
3. cleanup_old_bundles: Removes bundles older than 24 hours (runs regardless of upstream failures)
4. log_generation_summary: Logs patient demographics and generation statistics

Author: Apache Airflow POC
Version: 1.0.0
"""

import json
import logging
import os
import shutil
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.trigger_rule import TriggerRule

# Configure logging
logger = logging.getLogger(__name__)

# Synthea configuration
SYNTHEA_JAR = Path("/opt/synthea/synthea-with-dependencies.jar")
SYNTHEA_OUTPUT_DIR = Path("/opt/synthea/output")
BUNDLE_STORAGE_DIR = Path("/opt/airflow/output/bundles")

# Ensure storage directory exists
BUNDLE_STORAGE_DIR.mkdir(parents=True, exist_ok=True)


def generate_patient_data(**context) -> Dict[str, str]:
    """
    Generate synthetic patient data using Synthea JAR.
    
    Uses current timestamp as seed to ensure unique patients on each run.
    Executes Synthea with US Core R4 FHIR export enabled.
    
    Returns:
        Dict containing execution metadata (seed, timestamp, output_dir)
    
    Raises:
        RuntimeError: If Synthea execution fails
    """
    try:
        # Generate unique seed based on current time (milliseconds)
        seed = int(time.time() * 1000)
        execution_time = datetime.now()
        
        logger.info(f"Starting Synthea patient generation with seed: {seed}")
        
        # Clean previous output to avoid conflicts
        if SYNTHEA_OUTPUT_DIR.exists():
            logger.info(f"Cleaning previous output directory: {SYNTHEA_OUTPUT_DIR}")
            shutil.rmtree(SYNTHEA_OUTPUT_DIR)
        SYNTHEA_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        
        # Build Synthea command
        # -p 1: Generate 1 patient
        # --exporter.fhir.use_us_core_ig true: Use US Core Implementation Guide profiles
        # -s <seed>: Reproducible seed for this generation
        cmd = [
            "java",
            "-jar",
            str(SYNTHEA_JAR),
            "--exporter.fhir.use_us_core_ig",
            "true",
            "-p",
            "1",
            "-s",
            str(seed),
        ]
        
        logger.info(f"Executing Synthea command: {' '.join(cmd)}")
        
        # Execute Synthea with timeout (5 minutes max)
        result = subprocess.run(
            cmd,
            cwd=str(SYNTHEA_OUTPUT_DIR.parent),
            capture_output=True,
            text=True,
            timeout=300,
            check=True,
        )
        
        logger.info(f"Synthea execution completed successfully")
        logger.debug(f"Synthea stdout: {result.stdout[:500]}")
        
        # Store execution metadata for downstream tasks
        metadata = {
            "seed": str(seed),
            "execution_time": execution_time.isoformat(),
            "output_dir": str(SYNTHEA_OUTPUT_DIR),
        }
        
        # Push metadata to XCom for downstream tasks
        context["task_instance"].xcom_push(key="generation_metadata", value=metadata)
        
        return metadata
        
    except subprocess.TimeoutExpired as e:
        logger.error(f"Synthea execution timed out after 300 seconds")
        raise RuntimeError(f"Synthea execution timeout: {str(e)}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Synthea execution failed with return code {e.returncode}")
        logger.error(f"Stderr: {e.stderr}")
        raise RuntimeError(f"Synthea execution failed: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error during patient generation: {str(e)}")
        raise


def extract_and_store_bundle(**context) -> Optional[str]:
    """
    Extract all generated FHIR files and store in organized directory structure.
    
    Synthea generates 3 files with patterns:
    1. hospitalInformation{timestamp}.json - Hospital info
    2. {FirstName}{Num}_{LastName}{Num}_{patient_id}.json - Patient bundle (has person's name)
    3. practitionerInformation{timestamp}.json - Practitioner info
    
    Stores all files in: /opt/airflow/output/bundles/{patient_id}_{patient_name}/*.json
    
    Returns:
        Path to patient bundle file, or None if not found
    
    Raises:
        FileNotFoundError: If no FHIR files found in output
    """
    try:
        # Retrieve generation metadata from previous task
        metadata = context["task_instance"].xcom_pull(
            task_ids="generate_patient",
            key="generation_metadata"
        )
        
        if not metadata:
            logger.warning("No generation metadata found, using defaults")
            execution_time = datetime.now()
        else:
            execution_time = datetime.fromisoformat(metadata["execution_time"])
        
        logger.info("Searching for generated FHIR files")
        
        # Search for FHIR files in output directories
        source_dir = None
        json_files = []
        
        for subdir in ["fhir_r4", "fhir"]:
            search_dir = SYNTHEA_OUTPUT_DIR / subdir
            if search_dir.exists():
                json_files = list(search_dir.glob("*.json"))
                if json_files:
                    source_dir = search_dir
                    logger.info(f"Found {len(json_files)} FHIR files in: {search_dir}")
                    for f in json_files:
                        logger.info(f"  - {f.name}")
                    break
        
        if not json_files:
            error_msg = f"No FHIR files found in {SYNTHEA_OUTPUT_DIR}"
            logger.error(error_msg)
            raise FileNotFoundError(error_msg)
        
        # Identify the patient bundle file by filename pattern
        # Patient bundle has person's name pattern (not starting with hospital/practitioner)
        patient_bundle_file = None
        
        for json_file in json_files:
            filename = json_file.name
            # Patient file doesn't start with "hospital" or "practitioner"
            if not filename.startswith("hospitalInformation") and \
               not filename.startswith("practitionerInformation"):
                patient_bundle_file = json_file
                logger.info(f"Identified patient bundle: {filename}")
                break
        
        if not patient_bundle_file:
            error_msg = "No patient bundle found among generated files"
            logger.error(error_msg)
            logger.error(f"Available files: {[f.name for f in json_files]}")
            raise FileNotFoundError(error_msg)
        
        # Parse patient info from filename
        # Pattern: {FirstName}{Num}_{LastName}{Num}_{patient_id}.json
        # Example: Justin359_Roob72_b5ceadaf-3f35-da2f-1017-741e00f0e3dc.json
        filename = patient_bundle_file.stem  # Remove .json extension
        parts = filename.split("_")
        
        if len(parts) >= 3:
            # First part: FirstName with numbers (e.g., Justin359)
            # Second part: LastName with numbers (e.g., Roob72)
            # Remaining parts: patient_id (UUID with hyphens)
            first_name_part = parts[0]
            last_name_part = parts[1]
            patient_id = "_".join(parts[2:])  # Join remaining parts for UUID
            
            # Extract clean names (remove trailing numbers if desired, or keep as-is)
            patient_name = f"{first_name_part}_{last_name_part}"
            
            logger.info(f"Extracted patient info - Name: {patient_name}, ID: {patient_id}")
        else:
            # Fallback if pattern doesn't match
            logger.warning(f"Unexpected filename pattern: {filename}")
            patient_name = "unknown"
            patient_id = filename
        
        # Create folder named: {patient_id}_{patient_name}
        folder_name = f"{patient_id}_{patient_name}"
        patient_dir = BUNDLE_STORAGE_DIR / folder_name
        patient_dir.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Created storage directory: {patient_dir}")
        
        # Copy all JSON files to the patient directory
        copied_files = []
        for json_file in json_files:
            dest_path = patient_dir / json_file.name
            shutil.copy2(json_file, dest_path)
            copied_files.append(dest_path)
            logger.info(f"Copied: {json_file.name} -> {dest_path}")
        
        logger.info(f"Successfully stored {len(copied_files)} files in {patient_dir}")
        
        # Verify all 3 files are present
        if len(copied_files) != 3:
            logger.warning(f"Expected 3 files but found {len(copied_files)}")
        
        # Store patient bundle path for downstream tasks
        patient_bundle_dest = patient_dir / patient_bundle_file.name
        context["task_instance"].xcom_push(key="bundle_path", value=str(patient_bundle_dest))
        context["task_instance"].xcom_push(key="patient_folder", value=str(patient_dir))
        
        return str(patient_bundle_dest)
        
    except FileNotFoundError:
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse FHIR bundle JSON: {str(e)}")
        raise RuntimeError(f"Invalid FHIR bundle JSON: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error during bundle extraction: {str(e)}")
        raise


def cleanup_old_bundles(**context) -> Dict[str, int]:
    """
    Remove patient folders older than 24 hours.
    
    Scans storage directory and deletes entire patient folders (with all files)
    if any file has modification time > 24 hours ago.
    Runs regardless of upstream task failures (trigger_rule='all_done').
    
    Returns:
        Dict with cleanup statistics (deleted_folders, deleted_files, errors_count)
    """
    try:
        cutoff_time = time.time() - (24 * 60 * 60)  # 24 hours ago in seconds
        deleted_folders = 0
        deleted_files = 0
        error_count = 0
        
        logger.info(f"Starting cleanup of patient folders older than 24 hours")
        logger.info(f"Cutoff time: {datetime.fromtimestamp(cutoff_time).isoformat()}")
        
        # Walk through all patient folders
        if not BUNDLE_STORAGE_DIR.exists():
            logger.info("Bundle storage directory does not exist, nothing to clean")
            return {"deleted_folders": 0, "deleted_files": 0, "error_count": 0}
        
        for patient_dir in BUNDLE_STORAGE_DIR.iterdir():
            if not patient_dir.is_dir():
                continue
            
            try:
                # Check if any file in the folder is older than 24 hours
                folder_should_delete = False
                oldest_file_age = 0
                
                for file_path in patient_dir.glob("*.json"):
                    file_mtime = file_path.stat().st_mtime
                    file_age_hours = (time.time() - file_mtime) / 3600
                    
                    if file_mtime < cutoff_time:
                        folder_should_delete = True
                        oldest_file_age = max(oldest_file_age, file_age_hours)
                
                if folder_should_delete:
                    # Count files before deletion
                    file_count = len(list(patient_dir.glob("*.json")))
                    
                    logger.info(
                        f"Deleting patient folder: {patient_dir.name} "
                        f"({file_count} files, oldest: {oldest_file_age:.1f} hours)"
                    )
                    
                    # Delete entire folder with all contents
                    shutil.rmtree(patient_dir)
                    deleted_folders += 1
                    deleted_files += file_count
                    
            except Exception as e:
                logger.error(f"Error deleting folder {patient_dir}: {str(e)}")
                error_count += 1
        
        logger.info(
            f"Cleanup completed: {deleted_folders} folders deleted "
            f"({deleted_files} files), {error_count} errors"
        )
        
        return {
            "deleted_folders": deleted_folders,
            "deleted_files": deleted_files,
            "error_count": error_count
        }
        
    except Exception as e:
        logger.error(f"Unexpected error during cleanup: {str(e)}")
        return {"deleted_folders": 0, "deleted_files": 0, "error_count": 1}


def log_generation_summary(**context) -> None:
    """
    Log summary of patient generation including demographics and file information.
    
    Reads the generated bundle and extracts key patient information for logging.
    """
    try:
        bundle_path = context["task_instance"].xcom_pull(
            task_ids="extract_and_store_bundle",
            key="bundle_path"
        )
        
        if not bundle_path or not Path(bundle_path).exists():
            logger.warning("No bundle path found, skipping summary")
            return
        
        # Read bundle
        with open(bundle_path, "r") as f:
            bundle = json.load(f)
        
        # Extract patient information
        patient_info = {"id": "unknown", "name": "unknown", "gender": "unknown", "birthDate": "unknown"}
        
        if "entry" in bundle:
            for entry in bundle["entry"]:
                resource = entry.get("resource", {})
                if resource.get("resourceType") == "Patient":
                    patient_info["id"] = resource.get("id", "unknown")
                    patient_info["gender"] = resource.get("gender", "unknown")
                    patient_info["birthDate"] = resource.get("birthDate", "unknown")
                    
                    # Extract name
                    names = resource.get("name", [])
                    if names:
                        name = names[0]
                        given = " ".join(name.get("given", []))
                        family = name.get("family", "")
                        patient_info["name"] = f"{given} {family}".strip()
                    break
        
        # Count resources in bundle
        resource_count = len(bundle.get("entry", []))
        
        # Calculate file size
        file_size_kb = Path(bundle_path).stat().st_size / 1024
        
        # Log comprehensive summary
        logger.info("=" * 80)
        logger.info("PATIENT GENERATION SUMMARY")
        logger.info("=" * 80)
        logger.info(f"Patient ID: {patient_info['id']}")
        logger.info(f"Patient Name: {patient_info['name']}")
        logger.info(f"Gender: {patient_info['gender']}")
        logger.info(f"Birth Date: {patient_info['birthDate']}")
        logger.info(f"Total Resources: {resource_count}")
        logger.info(f"Bundle Size: {file_size_kb:.2f} KB")
        logger.info(f"Stored At: {bundle_path}")
        logger.info("=" * 80)
        
    except Exception as e:
        logger.error(f"Error generating summary: {str(e)}")
        # Don't raise - this is just logging, not critical


# Define default arguments for the DAG
default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(seconds=30),
    "execution_timeout": timedelta(minutes=5),
}

# Create the DAG
with DAG(
    dag_id="synthea_patient_generation",
    default_args=default_args,
    description="Generate synthetic patient data using Synthea every 10 seconds",
    schedule_interval="*/10 * * * *",  # Every 10 seconds (cron format: */10 for every 10 time units)
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,  # Sequential execution only
    tags=["synthea", "fhir", "healthcare", "poc"],
) as dag:
    
    # Task 1: Generate patient data using Synthea
    generate_patient = PythonOperator(
        task_id="generate_patient",
        python_callable=generate_patient_data,
        doc_md="""
        ### Generate Patient Data
        
        Executes Synthea JAR to generate synthetic patient data:
        - Uses timestamp-based seed for randomness
        - Generates 1 patient per run
        - Exports FHIR R4 bundle with US Core profiles
        - Timeout: 5 minutes
        """,
    )
    
    # Task 2: Extract and store all FHIR files
    extract_bundle = PythonOperator(
        task_id="extract_and_store_bundle",
        python_callable=extract_and_store_bundle,
        doc_md="""
        ### Extract and Store All FHIR Files
        
        Extracts all generated FHIR files and stores in patient-specific folder:
        - Searches for all JSON files in Synthea output (practitioner, hospital, patient)
        - Extracts patient ID and name from patient bundle
        - Stores in: bundles/{patient_id}_{patient_name}/*.json (all 3 files)
        """,
    )
    
    # Task 3: Cleanup old patient folders (runs even if upstream fails)
    cleanup_bundles = PythonOperator(
        task_id="cleanup_old_bundles",
        python_callable=cleanup_old_bundles,
        trigger_rule=TriggerRule.ALL_DONE,  # Run regardless of upstream status
        doc_md="""
        ### Cleanup Old Patient Folders
        
        Removes patient folders older than 24 hours:
        - Scans all patient folders in storage directory
        - Deletes entire folders (with all 3 JSON files) if older than 24 hours
        - Folder structure: {patient_id}_{patient_name}/
        - Runs regardless of upstream task status
        """,
    )
    
    # Task 4: Log generation summary
    log_summary = PythonOperator(
        task_id="log_generation_summary",
        python_callable=log_generation_summary,
        doc_md="""
        ### Log Generation Summary
        
        Logs comprehensive patient generation summary:
        - Patient demographics (name, ID, gender, birth date)
        - Resource count in bundle
        - Bundle file size
        - Storage location
        """,
    )
    
    # Define task dependencies
    generate_patient >> extract_bundle >> [cleanup_bundles, log_summary]
