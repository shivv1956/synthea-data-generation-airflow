# FHIR Data Pipeline Architecture

## Pipeline Overview

```
                    SYNTHEA SYNTHETIC DATA GENERATION
                    ┌─────────────────────────────────┐
                    │  synthea_generation_dag.py      │
                    │  Schedule: Every 10 seconds     │
                    │  - Generate FHIR R4 bundles     │
                    │  - Save to local storage        │
                    │  - Cleanup old files (24h TTL)  │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    LOCAL FILE SYSTEM (Temporary)
                    ┌─────────────────────────────────┐
                    │  output/bundles/                │
                    │  - Patient bundles (JSON)       │
                    │  - Hospital info                │
                    │  - Practitioner info            │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    AWS S3 UPLOAD
                    ┌─────────────────────────────────┐
                    │  s3_upload_dag.py               │
                    │  Schedule: Every 30 seconds     │
                    │  - Scan for new bundles         │
                    │  - Upload to S3                 │
                    │  - Mark as uploaded             │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    AWS S3 (Persistent Storage)
                    ┌─────────────────────────────────┐
                    │  s3://synthea-fhir-data-dump/   │
                    │  raw/patients/                  │
                    │  - *.json (FHIR bundles)        │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    SNOWFLAKE RAW LAYER LOAD
                    ┌─────────────────────────────────┐
                    │  s3_to_snowflake_load_dag.py    │ ← NEW
                    │  Schedule: Every 5 minutes      │
                    │  - List new S3 files            │
                    │  - COPY INTO Snowflake          │
                    │  - Track watermark              │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    SNOWFLAKE RAW LAYER
                    ┌─────────────────────────────────┐
                    │  RAW.FHIR_BUNDLES              │
                    │  - FILE_KEY (PK)               │
                    │  - BUNDLE_DATA (VARIANT)       │
                    │  - LOADED_AT, S3_LAST_MODIFIED │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    DBT TRANSFORMATIONS
                    ┌─────────────────────────────────┐
                    │  dbt_transform_fhir_dag.py     │ ← NEW
                    │  Schedule: Every 10 minutes     │
                    │  - Wait for S3 loader           │
                    │  - Run dbt staging models       │
                    │  - Run dbt intermediate models  │
                    │  - Run dbt marts models         │
                    │  - Run dbt tests                │
                    └────────────┬────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ▼                         ▼
        SNOWFLAKE STAGING          SNOWFLAKE INTERMEDIATE
        (18 Incremental Models)    (4 Full Refresh Models)
        ┌──────────────────────┐   ┌──────────────────────┐
        │ STG_PATIENTS         │   │ INT_REFERENCE_MAP    │
        │ STG_ENCOUNTERS       │   │ INT_CLAIMS_ENRICHED  │
        │ STG_CONDITIONS       │   │ INT_MEDICATION_REASONS│
        │ STG_OBSERVATIONS     │   │ INT_PROCEDURE_REASONS│
        │ STG_MEDICATIONS      │   └──────────┬───────────┘
        │ STG_PROCEDURES       │              │
        │ STG_IMMUNIZATIONS    │              │
        │ STG_ALLERGIES        │              │
        │ STG_CAREPLANS        │              │
        │ STG_DEVICES          │              │
        │ STG_SUPPLIES         │              │
        │ STG_IMAGING_STUDIES  │              │
        │ STG_CLAIMS           │              │
        │ STG_CLAIMS_TRANS...  │              │
        │ STG_PAYERS           │              │
        │ STG_PAYER_TRANS...   │              │
        │ STG_PROVIDERS        │              │
        │ STG_ORGANIZATIONS    │              │
        └──────────┬───────────┘              │
                   └──────────────┬───────────┘
                                  │
                                  ▼
                    SNOWFLAKE MARTS (Star Schema)
                    ┌─────────────────────────────────┐
                    │  DIMENSION TABLE                │
                    │  - DIM_PATIENTS                 │
                    │    (Master patient data)        │
                    └────────────┬────────────────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
           ┌────────────┐ ┌────────────┐ ┌────────────┐
           │ FACT TABLE │ │ FACT TABLE │ │ FACT TABLE │
           │ FCT_       │ │ FCT_       │ │ FCT_       │
           │ ENCOUNTERS │ │ MEDICATIONS│ │ PROCEDURES │
           └────────────┘ └────────────┘ └────────────┘
                    │                         │
                    └────────────┬────────────┘
                                 │
                                 ▼
                          ┌────────────┐
                          │ FACT TABLE │
                          │ FCT_       │
                          │OBSERVATIONS│
                          └────────────┘
                                 │
                                 ▼
                    BI / ANALYTICS TOOLS
                    ┌─────────────────────────────────┐
                    │  Tableau / Power BI / Looker    │
                    │  - Patient cohort analysis      │
                    │  - Cost analytics               │
                    │  - Clinical outcomes            │
                    │  - Population health metrics    │
                    └─────────────────────────────────┘
```

## DAG Execution Timeline

```
Time:     0s     10s    20s    30s    40s    50s    60s    ...    5m     ...    10m
          │       │      │      │      │      │      │            │            │
Synthea:  ●───────●──────●──────●──────●──────●──────●────────────●────────────● (Every 10s)
          │       │      │      │      │      │      │            │            │
S3Upload: ●───────────────────────●─────────────────────────●──────────────────● (Every 30s)
          │                      │                    │                         │
S3→Snow:  ●───────────────────────────────────────────────────────●────────────● (Every 5m)
          │                                                        │            │
dbt:      ●────────────────────────────────────────────────────────────────────● (Every 10m)
          │                                                                     │
          └─────────────────────────────────────────────────────────────────────┘
          Generation → Upload → Load → Transform (Total: ~15-16 minutes)
```

## Data Volume Estimates

### Generation Rate (Synthea)
- **Frequency**: 1 patient every 10 seconds
- **Files per patient**: 3 (bundle + hospital + practitioner)
- **Size per patient**: ~50-100KB JSON
- **Daily volume**: ~8,640 patients, ~750MB-1.5GB

### S3 Storage
- **Growth rate**: ~1.5GB/day
- **Monthly**: ~45GB
- **Yearly**: ~550GB

### Snowflake Storage
- **RAW layer**: ~550GB/year (uncompressed JSON)
- **STAGING layer**: ~350GB/year (compressed, columnar)
- **INTERMEDIATE layer**: ~50GB (reference tables)
- **MARTS layer**: ~200GB (fact + dimension tables)
- **Total**: ~1.15TB/year

## Error Handling Strategy

```
┌──────────────────────────────────────────────────────────┐
│  Task Failure                                            │
└───────────────────┬──────────────────────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Retry Logic         │
         │  - Attempts: 1-2     │
         │  - Delay: 1-2 min    │
         └──────────┬───────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Still Failing?      │
         └───┬──────────────┬───┘
             │              │
          YES│              │NO
             │              │
             ▼              ▼
    ┌────────────────┐  ┌────────────────┐
    │  Alert Team    │  │  Mark Success  │
    │  - Email       │  │  - Continue    │
    │  - Slack       │  │                │
    └────────────────┘  └────────────────┘
```

## Monitoring Dashboard (Recommended Metrics)

### Real-Time Metrics
- DAG run success rate (last 24h)
- Average execution time per DAG
- Current backlog size (S3 files waiting to load)
- dbt model execution times
- dbt test pass/fail rates

### Data Quality Metrics
- Null value percentages in critical fields
- Referential integrity check failures
- Data freshness (time since last update)
- Row count trends (staging → marts)

### Infrastructure Metrics
- Airflow worker CPU/memory usage
- Snowflake warehouse credit consumption
- S3 storage costs
- Network transfer costs

## Security Considerations

### Credentials Management
- ✓ Environment variables (not hardcoded)
- ✓ Airflow Connections (encrypted)
- ✓ Snowflake role-based access control
- ✓ S3 bucket policies

### Data Protection
- ✓ Synthetic data only (no PHI/PII)
- ✓ Encryption at rest (S3, Snowflake)
- ✓ Encryption in transit (HTTPS, TLS)
- ⚠ Consider adding: VPC endpoints, private subnets

### Compliance (for Production)
- [ ] HIPAA compliance review (if real data)
- [ ] Data retention policies
- [ ] Audit logging
- [ ] Access control review

## Disaster Recovery

### Backup Strategy
- **S3**: Versioning enabled (automatic)
- **Snowflake**: Time Travel (90 days)
- **Airflow**: Git version control for DAGs
- **dbt**: Git version control for models

### Recovery Scenarios

#### Scenario 1: S3 Loader Fails
- Impact: Data accumulates in S3
- Recovery: Fix issue, loader will catch up using watermark
- Data loss: None

#### Scenario 2: dbt Models Fail
- Impact: MARTS layer becomes stale
- Recovery: Fix model, re-run dbt DAG
- Data loss: None (source data intact)

#### Scenario 3: Snowflake Outage
- Impact: Pipeline stalls at S3 loader
- Recovery: Wait for Snowflake, retry tasks
- Data loss: None (buffered in S3)

## Scalability Roadmap

### Phase 1: Current (Proof of Concept)
- ✓ Single Airflow worker
- ✓ LocalExecutor
- ✓ Sequential DAG execution
- ✓ Handles 8K patients/day

### Phase 2: Production Ready (Next 3 Months)
- [ ] Multiple Airflow workers
- [ ] CeleryExecutor
- [ ] Parallel DAG execution
- [ ] Handles 100K patients/day

### Phase 3: Enterprise Scale (6-12 Months)
- [ ] Kubernetes-based Airflow
- [ ] Auto-scaling workers
- [ ] Multi-region deployment
- [ ] Handles 1M+ patients/day

## Cost Optimization Tips

### Airflow
- Use LocalExecutor for dev/test (no Redis/workers)
- Schedule maintenance windows for resource-intensive tasks
- Implement task-level resource limits

### Snowflake
- Use auto-suspend warehouses (1 minute idle)
- Right-size warehouse for workload (X-Small for POC)
- Cluster keys on large fact tables
- Materialized views for expensive queries

### AWS S3
- Use S3 Intelligent-Tiering for old data
- Implement lifecycle policies (30d → Glacier)
- Enable S3 Transfer Acceleration if multi-region

---

**Last Updated**: January 7, 2026  
**Version**: 1.0  
**Status**: Implementation Complete ✓
