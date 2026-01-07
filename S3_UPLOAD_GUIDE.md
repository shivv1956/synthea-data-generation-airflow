# AWS S3 Upload Configuration Guide

This guide explains how to configure AWS credentials and customize the S3 upload DAG.

## 📋 Prerequisites

1. AWS Account with S3 access
2. S3 bucket created (or use existing bucket)
3. AWS credentials (Access Key ID and Secret Access Key)

## 🔐 Step 1: Configure AWS Credentials in Airflow

### Option A: Using Airflow UI (Recommended)

1. Access Airflow UI: http://localhost:8080
2. Navigate to: **Admin** → **Connections**
3. Click **+** (Add Connection)
4. Fill in the connection details:
   - **Connection Id**: `aws_default`
   - **Connection Type**: `Amazon Web Services`
   - **AWS Access Key ID**: Your AWS access key
   - **AWS Secret Access Key**: Your AWS secret key
   - **Extra**: `{"region_name": "us-east-1"}` (change region as needed)
5. Click **Save**

### Option B: Using Environment Variables

Add to `.env` file:
```bash
AIRFLOW_CONN_AWS_DEFAULT='aws://YOUR_ACCESS_KEY:YOUR_SECRET_KEY@?region_name=us-east-1'
```

### Option C: Using AWS IAM Role (for EC2/ECS)

If running on AWS infrastructure, use IAM roles instead of credentials:
```bash
AWS_CONN_ID=aws_default
# No credentials needed - uses instance role
```

## 📦 Step 2: Configure S3 Bucket Settings

Edit `.env` file:

```bash
# S3 Bucket Configuration
AWS_S3_BUCKET=your-bucket-name           # Change to your bucket name
AWS_S3_PREFIX=raw/fhir                   # Change prefix as needed
AWS_CONN_ID=aws_default                  # Connection ID from Step 1

# Enable/Disable Transformations
ENABLE_TRANSFORMATIONS=false             # Set to 'true' to enable
```

## 📂 S3 Structure

Files will be uploaded to:
```
s3://your-bucket-name/raw/fhir/patients/{patient_id}_{patient_name}/
    ├── hospitalInformation{timestamp}.json
    ├── {FirstName}_{LastName}_{patient_id}.json
    └── practitionerInformation{timestamp}.json
```

Example:
```
s3://synthea-patient-data/raw/fhir/patients/b5ceadaf-3f35-da2f-1017-741e00f0e3dc_Justin359_Roob72/
    ├── hospitalInformation1767176740699.json
    ├── Justin359_Roob72_b5ceadaf-3f35-da2f-1017-741e00f0e3dc.json
    └── practitionerInformation1767176740699.json
```

## 🔧 Step 3: Customize Transformations

To add data transformations before upload, edit `dags/s3_upload_dag.py`:

### Enable Transformations
```bash
ENABLE_TRANSFORMATIONS=true
```

### Modify Transform Function

Edit the `transform_data()` function in `dags/s3_upload_dag.py`:

```python
def transform_data(**context) -> Dict[str, int]:
    """Apply your custom transformations here"""
    
    for folder_name in new_folders:
        patient_dir = BUNDLE_STORAGE_DIR / folder_name
        
        for json_file in patient_dir.glob("*.json"):
            with json_file.open("r") as f:
                data = json.load(f)
            
            # Example 1: Redact sensitive information
            if "entry" in data:
                for entry in data["entry"]:
                    resource = entry.get("resource", {})
                    if resource.get("resourceType") == "Patient":
                        # Remove SSN or other PII
                        resource.pop("identifier", None)
            
            # Example 2: Add metadata
            data["metadata"] = {
                "processed_at": datetime.now().isoformat(),
                "source": "synthea",
                "version": "1.0"
            }
            
            # Example 3: Validate FHIR schema
            from fhir.resources.bundle import Bundle
            try:
                Bundle.parse_obj(data)  # Validates FHIR structure
            except Exception as e:
                logger.error(f"Invalid FHIR bundle: {e}")
                continue
            
            # Write transformed data back
            with json_file.open("w") as f:
                json.dump(data, f, indent=2)
```

### Common Transformation Examples

#### 1. Remove PII (De-identification)
```python
# Remove patient names, addresses, SSN
for entry in data.get("entry", []):
    resource = entry.get("resource", {})
    if resource.get("resourceType") == "Patient":
        resource["name"] = [{"text": "REDACTED"}]
        resource.pop("address", None)
        resource.pop("telecom", None)
```

#### 2. Data Enrichment
```python
# Add custom fields
data["processing_metadata"] = {
    "environment": "production",
    "dag_run_id": context["dag_run"].run_id,
    "processed_timestamp": datetime.now().isoformat()
}
```

#### 3. Format Conversion
```python
# Convert to NDJSON (newline-delimited JSON)
ndjson_content = "\n".join(
    json.dumps(entry) for entry in data.get("entry", [])
)
```

#### 4. Validation and Filtering
```python
# Only upload if patient meets criteria
has_conditions = any(
    entry.get("resource", {}).get("resourceType") == "Condition"
    for entry in data.get("entry", [])
)
if not has_conditions:
    logger.info("Skipping patient with no conditions")
    continue
```

## 🔄 Step 4: Rebuild and Restart

After configuration changes:

```bash
cd /home/shiva/repos/hapi-server
docker-compose down
docker-compose up --build -d
```

## 📊 Step 5: Monitor Uploads

### View DAG in Airflow UI
1. Go to http://localhost:8080
2. Find DAG: `s3_upload_patient_data`
3. Check task logs for upload progress

### Verify S3 Uploads
```bash
# Using AWS CLI
aws s3 ls s3://your-bucket-name/raw/fhir/patients/

# Count uploaded files
aws s3 ls s3://your-bucket-name/raw/fhir/patients/ --recursive | wc -l
```

### Check Local Marker Files
```bash
# Folders with .uploaded marker have been processed
ls -la output/bundles/*/.uploaded
```

## 🐛 Troubleshooting

### Issue: "No AWS credentials found"
**Solution**: Configure AWS connection in Airflow UI (see Step 1)

### Issue: "Access Denied" when uploading
**Solution**: Check IAM permissions for S3 bucket:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name/*",
        "arn:aws:s3:::your-bucket-name"
      ]
    }
  ]
}
```

### Issue: DAG not appearing
**Solution**: Check logs for syntax errors:
```bash
docker-compose logs airflow-scheduler | grep s3_upload
```

### Issue: Transformations not running
**Solution**: Verify `ENABLE_TRANSFORMATIONS=true` in `.env` and restart services

## 🎯 Advanced Configuration

### Change Upload Frequency
Edit `dags/s3_upload_dag.py`:
```python
schedule_interval="*/30 * * * *",  # Every 30 seconds (default)
# Change to:
schedule_interval="@hourly",        # Every hour
schedule_interval="0 */6 * * *",    # Every 6 hours
```

### Parallel Uploads
Increase concurrent uploads:
```python
max_active_runs=3,  # Default: 3 parallel DAG runs
# Change to:
max_active_runs=10,  # Allow 10 parallel uploads
```

### Add File Compression
```python
import gzip

# In transform_data or upload_to_s3:
with gzip.open(f"{json_file}.gz", "wt") as f:
    json.dump(data, f)
# Upload .gz file instead
```

### Use S3 Lifecycle Policies
Configure automatic archival/deletion in AWS:
- Archive to Glacier after 30 days
- Delete after 365 days
- Transition to Intelligent Tiering

## 📝 Summary

1. ✅ Configure AWS credentials in Airflow
2. ✅ Set S3 bucket and prefix in `.env`
3. ✅ Customize transformations in `s3_upload_dag.py`
4. ✅ Rebuild containers with `docker-compose up --build -d`
5. ✅ Monitor uploads in Airflow UI and AWS Console

The S3 upload DAG will automatically process new patient data every 30 seconds and upload to your configured S3 bucket!
