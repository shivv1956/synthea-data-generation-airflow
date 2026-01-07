# Snowflake Schema Documentation

## Schema Structure

```
SYNTHEA (Database)
├── RAW
│   ├── FHIR_BUNDLES (VARIANT JSON storage)
│   └── LOAD_WATERMARK (incremental tracking)
│
├── STAGING (Incremental models - merge strategy)
│   ├── STG_PATIENTS
│   ├── STG_ENCOUNTERS
│   ├── STG_CONDITIONS
│   ├── STG_OBSERVATIONS
│   ├── STG_MEDICATIONS
│   ├── STG_PROCEDURES
│   ├── STG_IMMUNIZATIONS
│   ├── STG_ALLERGIES
│   ├── STG_CAREPLANS
│   ├── STG_DEVICES
│   ├── STG_SUPPLIES
│   ├── STG_IMAGING_STUDIES
│   ├── STG_CLAIMS
│   ├── STG_CLAIMS_TRANSACTIONS
│   ├── STG_PAYERS
│   ├── STG_PAYER_TRANSITIONS
│   ├── STG_PROVIDERS
│   └── STG_ORGANIZATIONS
│
├── INTERMEDIATE (Full refresh - table materialization)
│   ├── INT_REFERENCE_MAP (UUID lookups)
│   ├── INT_CLAIMS_ENRICHED (financial aggregations)
│   ├── INT_MEDICATION_REASONS (condition linkage)
│   └── INT_PROCEDURE_REASONS (condition linkage)
│
└── MARTS (Analytics-ready - table materialization)
    ├── DIM_PATIENTS (patient dimension)
    ├── FCT_ENCOUNTERS (encounter facts)
    ├── FCT_MEDICATIONS (medication facts)
    ├── FCT_PROCEDURES (procedure facts)
    └── FCT_OBSERVATIONS (observation facts)
```

## Table Relationships

### Fact Tables (MARTS)

#### FCT_ENCOUNTERS
```sql
FCT_ENCOUNTERS
├── PK: encounter_key (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_key
├── FK: organization_id → STG_ORGANIZATIONS.id
├── FK: provider_id → STG_PROVIDERS.id
└── Metrics: base_encounter_cost, total_claim_cost, payer_coverage
```

#### FCT_MEDICATIONS
```sql
FCT_MEDICATIONS
├── PK: medication_key (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_key
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_key
└── Metrics: cost_per_dispense, total_cost, payer_coverage
```

#### FCT_PROCEDURES
```sql
FCT_PROCEDURES
├── PK: procedure_key (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_key
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_key
└── Metrics: base_cost
```

#### FCT_OBSERVATIONS
```sql
FCT_OBSERVATIONS
├── PK: observation_key (surrogate)
├── FK: patient_id → DIM_PATIENTS.patient_key
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_key
└── Metrics: numeric_value, observation_value
```

### Dimension Table (MARTS)

#### DIM_PATIENTS
```sql
DIM_PATIENTS
├── PK: patient_key (UUID)
├── Attributes: demographics, address, identifiers
└── Metrics: lifetime_healthcare_expenses, lifetime_healthcare_coverage
```

## Star Schema

```
                    ┌─────────────────┐
                    │  DIM_PATIENTS   │
                    │                 │
                    │ patient_key (PK)│
                    │ first_name      │
                    │ last_name       │
                    │ birth_date      │
                    │ age             │
                    │ gender          │
                    │ race            │
                    │ ...             │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
         ┌──────────▼─────────┐  ┌───▼────────────────┐
         │  FCT_ENCOUNTERS    │  │  FCT_MEDICATIONS   │
         │                    │  │                    │
         │ encounter_key (PK) │  │ medication_key (PK)│
         │ patient_id (FK)───┼──┤ patient_id (FK)    │
         │ organization_id    │  │ encounter_id (FK)  │
         │ provider_id        │  │ medication_code    │
         │ encounter_class    │  │ total_cost         │
         │ total_claim_cost   │  │ payer_coverage     │
         │ payer_coverage     │  └────────────────────┘
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐  ┌────────────────────┐
         │  FCT_PROCEDURES    │  │  FCT_OBSERVATIONS  │
         │                    │  │                    │
         │ procedure_key (PK) │  │ observation_key(PK)│
         │ patient_id (FK)───┼──┤ patient_id (FK)    │
         │ encounter_id (FK)  │  │ encounter_id (FK)  │
         │ procedure_code     │  │ observation_code   │
         │ base_cost          │  │ numeric_value      │
         └────────────────────┘  └────────────────────┘
```

## Key Columns by Table

### STAGING.STG_PATIENTS
| Column | Type | Description |
|--------|------|-------------|
| id | VARCHAR | Patient UUID (PK) |
| birthdate | DATE | Date of birth |
| deathdate | TIMESTAMP | Date of death (if deceased) |
| ssn | VARCHAR | Social Security Number |
| first | VARCHAR | First name |
| last | VARCHAR | Last name |
| gender | VARCHAR | M/F |
| race | VARCHAR | Patient race |
| ethnicity | VARCHAR | Patient ethnicity |
| address | VARCHAR | Street address |
| city | VARCHAR | City |
| state | VARCHAR | State |
| zip | VARCHAR | Zip code |
| lat | FLOAT | Latitude |
| lon | FLOAT | Longitude |
| loaded_at | TIMESTAMP | When data was loaded |

### STAGING.STG_ENCOUNTERS
| Column | Type | Description |
|--------|------|-------------|
| id | VARCHAR | Encounter UUID (PK) |
| start | TIMESTAMP | Encounter start time |
| stop | TIMESTAMP | Encounter end time |
| patient | VARCHAR | Patient UUID (FK) |
| organization | VARCHAR | Organization UUID (FK) |
| provider | VARCHAR | Provider UUID (FK) |
| encounterclass | VARCHAR | ambulatory, emergency, inpatient, etc. |
| code | VARCHAR | Encounter type code |
| description | VARCHAR | Encounter description |
| reasoncode | VARCHAR | Reason for visit code |
| loaded_at | TIMESTAMP | When data was loaded |

### STAGING.STG_CONDITIONS
| Column | Type | Description |
|--------|------|-------------|
| id | VARCHAR | Condition UUID (PK) |
| start | DATE | Condition onset date |
| stop | DATE | Condition resolution date |
| patient | VARCHAR | Patient UUID (FK) |
| encounter | VARCHAR | Encounter UUID (FK) |
| system | VARCHAR | Code system (SNOMED-CT) |
| code | VARCHAR | Condition code |
| description | VARCHAR | Condition description |
| loaded_at | TIMESTAMP | When data was loaded |

### STAGING.STG_OBSERVATIONS
| Column | Type | Description |
|--------|------|-------------|
| id | VARCHAR | Observation UUID (PK) |
| date | TIMESTAMP | Observation date/time |
| patient | VARCHAR | Patient UUID (FK) |
| encounter | VARCHAR | Encounter UUID (FK) |
| category | VARCHAR | Observation category |
| code | VARCHAR | LOINC code |
| description | VARCHAR | Observation description |
| value | VARCHAR | Observation value |
| units | VARCHAR | Units of measure |
| type | VARCHAR | numeric or text |
| loaded_at | TIMESTAMP | When data was loaded |

### INTERMEDIATE.INT_REFERENCE_MAP
| Column | Type | Description |
|--------|------|-------------|
| resource_id | VARCHAR | UUID of resource (PK) |
| resource_type | VARCHAR | Type (Patient, Encounter, etc.) |
| patient_id | VARCHAR | Associated patient |
| encounter_id | VARCHAR | Associated encounter |
| condition_id | VARCHAR | Associated condition code |
| display_name | VARCHAR | Human-readable name |
| last_updated | TIMESTAMP | Last update time |

### MARTS.DIM_PATIENTS
| Column | Type | Description |
|--------|------|-------------|
| patient_key | VARCHAR | Patient UUID (PK) |
| ssn | VARCHAR | Social Security Number |
| full_name | VARCHAR | Concatenated full name |
| gender | VARCHAR | M/F |
| birth_date | DATE | Date of birth |
| death_date | TIMESTAMP | Date of death (if deceased) |
| age | INT | Current age or age at death |
| is_alive | BOOLEAN | Living status |
| race | VARCHAR | Patient race |
| ethnicity | VARCHAR | Patient ethnicity |
| city | VARCHAR | City of residence |
| state | VARCHAR | State of residence |
| lifetime_healthcare_expenses | FLOAT | Total costs |
| lifetime_healthcare_coverage | FLOAT | Insurance paid |
| patient_out_of_pocket | FLOAT | Patient responsibility |

### MARTS.FCT_ENCOUNTERS
| Column | Type | Description |
|--------|------|-------------|
| encounter_key | VARCHAR | Encounter UUID (PK) |
| patient_id | VARCHAR | Patient UUID (FK) |
| organization_id | VARCHAR | Facility UUID (FK) |
| provider_id | VARCHAR | Provider UUID (FK) |
| encounter_start | TIMESTAMP | Start time |
| encounter_stop | TIMESTAMP | End time |
| encounter_duration_hours | INT | Duration in hours |
| encounter_class | VARCHAR | Visit type |
| encounter_code | VARCHAR | Type code |
| base_encounter_cost | FLOAT | Base cost |
| total_claim_cost | FLOAT | Total cost |
| payer_coverage | FLOAT | Insurance paid |
| patient_responsibility | FLOAT | Patient owes |

## Query Examples

### Patient Summary
```sql
SELECT 
    full_name,
    age,
    gender,
    race,
    city,
    state,
    lifetime_healthcare_expenses,
    lifetime_healthcare_coverage
FROM SYNTHEA.MARTS.DIM_PATIENTS
WHERE is_alive = TRUE
ORDER BY lifetime_healthcare_expenses DESC
LIMIT 10;
```

### Encounter Volume by Type
```sql
SELECT 
    encounter_class,
    COUNT(*) as encounter_count,
    AVG(total_claim_cost) as avg_cost,
    SUM(total_claim_cost) as total_cost
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS
GROUP BY encounter_class
ORDER BY encounter_count DESC;
```

### Top Medications by Cost
```sql
SELECT 
    medication_description,
    COUNT(*) as prescription_count,
    AVG(total_cost) as avg_cost,
    SUM(total_cost) as total_cost
FROM SYNTHEA.MARTS.FCT_MEDICATIONS
GROUP BY medication_description
ORDER BY total_cost DESC
LIMIT 20;
```

### Patient Visit History
```sql
SELECT 
    p.full_name,
    e.encounter_start,
    e.encounter_class,
    e.encounter_description,
    e.total_claim_cost
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_PATIENTS p
    ON e.patient_id = p.patient_key
WHERE p.patient_key = '<PATIENT_UUID>'
ORDER BY e.encounter_start DESC;
```

### Lab Results for Patient
```sql
SELECT 
    observation_date,
    observation_description,
    observation_value,
    observation_units
FROM SYNTHEA.MARTS.FCT_OBSERVATIONS
WHERE patient_id = '<PATIENT_UUID>'
    AND observation_category = 'laboratory'
ORDER BY observation_date DESC;
```
