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
    ├── DIM_PROVIDER (clinician dimension)
    ├── DIM_ORGANIZATION (facility dimension)
    ├── DIM_PAYER (insurance dimension)
    ├── DIM_DATE (calendar dimension)
    ├── DIM_ENCOUNTER_CLASS (lookup dimension)
    ├── FCT_ENCOUNTERS (encounter facts - star schema center)
    ├── FCT_MEDICATIONS (medication facts)
    ├── FCT_PROCEDURES (procedure facts)
    └── FCT_OBSERVATIONS (observation facts)
```

## Table Relationships

### Fact Tables (MARTS)

#### FCT_ENCOUNTERS
```sql
FCT_ENCOUNTERS (Central Fact Table)
├── PK: encounter_id (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_id
├── FK: provider_id → DIM_PROVIDER.provider_id
├── FK: organization_id → DIM_ORGANIZATION.organization_id
├── FK: payer_id → DIM_PAYER.payer_id
├── FK: start_date_key → DIM_DATE.date_key
├── FK: end_date_key → DIM_DATE.date_key
└── Metrics: base_encounter_cost, total_claim_cost, payer_coverage, patient_responsibility
```

#### FCT_MEDICATIONS
```sql
FCT_MEDICATIONS
├── PK: medication_key (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_id
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_id
└── Metrics: cost_per_dispense, total_cost, payer_coverage
```

#### FCT_PROCEDURES
```sql
FCT_PROCEDURES
├── PK: procedure_key (UUID)
├── FK: patient_id → DIM_PATIENTS.patient_id
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_id
└── Metrics: base_cost
```

#### FCT_OBSERVATIONS
```sql
FCT_OBSERVATIONS
├── PK: observation_key (surrogate)
├── FK: patient_id → DIM_PATIENTS.patient_id
├── FK: encounter_id → FCT_ENCOUNTERS.encounter_id
└── Metrics: numeric_value, observation_value
```

### Dimension Tables (MARTS)

#### DIM_PATIENTS
```sql
DIM_PATIENTS
├── PK: patient_id (UUID)
├── Attributes: demographics, address, identifiers
└── Metrics: lifetime_healthcare_expenses, lifetime_healthcare_coverage
```

#### DIM_PROVIDER
```sql
DIM_PROVIDER
┌──────────────────┐  ┌──────────────────┐  ┌───────────────────┐
│   DIM_PATIENT    │  │   DIM_PROVIDER   │  │ DIM_ORGANIZATION  │
│                  │  │                  │  │                   │
│ patient_id (PK)  │  │ provider_id (PK) │  │ organization_id   │
│ first_name       │  │ name             │  │ (PK)              │
│ last_name        │  │ gender           │  │ name              │
│ gender           │  │ speciality       │  │ address           │
│ birth_date       │  │ address          │  │ city              │
│ race             │  │ city             │  │ state             │
│ ethnicity        │  │ state            │  │ phone             │
└────────┬─────────┘  └────────┬─────────┘  └─────────┬─────────┘
         │                     │                      │
         │    ┌────────────────┼──────────────────────┤
         │    │                │                      │
    ┌────▼────▼────────────────▼──────────────────────▼────┐
    │              FCT_ENCOUNTERS (Central Fact)           │
    │                                                       │
    │ encounter_id (PK)                                     │
    │ patient_id (FK) ───────────────┐                     │
    │ provider_id (FK) ──────────────┼─────┐               │
    │ organization_id (FK) ───────────┼─────┼──┐            │
    │ payer_id (FK) ──────────────────┼─────┼──┼──┐         │
    │ start_date_key (FK) ────────────┼─────┼──┼──┼──┐      │
    │ end_date_key (FK) ──────────────┼─────┼──┼──┼──┼──┐   │
    │ encounter_class                 │     │  │  │  │  │   │
    │ code                            │     │  │  │  │  │   │
    │ description                     │     │  │  │  │  │   │
    │ total_claim_cost                │     │  │  │  │  │   │
    │ payer_coverage                  │     │  │  │  │  │   │
    └─────────────┬───────────────────┘     │  │  │  │  │   │
                  │                         │  │  │  │  │   │
                  │                         │  │  │  │  │   │
   ┌──────────────┼─────────────────────────┘  │  │  │  │   │
   │              │                             │  │  │  │   │
   │  ┌───────────┼─────────────────────────────┘  │  │  │   │
   │  │           │                                │  │  │   │
   │  │  ┌────────┼────────────────────────────────┘  │  │   │
   │  │  │        │                                   │  │   │
   │  │  │  ┌─────┼───────────────────────────────────┘  │   │
   │  │  │  │     │                                      │   │
   ▼  ▼  ▼  ▼     ▼                                      ▼   ▼
┌────────────┐ ┌──────────────┐  ┌────────────────┐  ┌────────┐
│ DIM_PAYER  │ │DIM_ENCOUNTER │  │   DIM_DATE     │  │DIM_DATE│
│            │ │   _CLASS     │  │                │  │        │
│payer_id    │ │              │  │ date_key (PK)  │  │date_key│
│(PK)        │ │encounter_    │  │ date           │  │(PK)    │
│name        │ │class_code    │  │ year           │  │(end)   │
│ownership   │ │(PK)          │  │ quarter        │  │        │
│address     │ │encounter_    │  │ month          │  │        │
│city        │ │class_        │  │ week           │  │        │
│state       │ │friendly_name │  │ day_of_week    │  │        │
└────────────┘ └──────────────┘  └────────────────┘  └────────┘

          ┌──────────────────────────┐
          │  Other Fact Tables       │
          │  (linked via FKs)        │
          ├──────────────────────────┤
          │ FCT_MEDICATIONS          │
          │ FCT_PROCEDURES           │
          │ FCT_OBSERVATIONS         │
          └──────

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
| patient_id | VARCHAR | Patient UUID (PK) |
| ssn | VARCHAR | Social Security Number |
| first_name | VARCHAR | First name |
| last_name | VARCHAR | Last name |
| full_name | VARCHAR | Concatenated full name |
| gender | VARCHAR | M/F |
| birth_date | DATE | Date of birth |
| death_date | TIMESTAMP | Date of death (if deceased) |
| age | INT | Current age or age at death |
| is_alive | BOOLEAN | Living status |
| race | VARCHAR | Patient race |
| ethnicity | VARCHAR | Patient ethnicity |
| marital_status | VARCHAR | Marital status |
| city | VARCHAR | City of residence |
| state | VARCHAR | State of residence |
| zip | VARCHAR | Zip code |
| latitude | FLOAT | Latitude |
| longitude | FLOAT | Longitude |
| lifetime_healthcare_expenses | FLOAT | Total costs |
| lifetime_healthcare_coverage | FLOAT | Insurance paid |
| patient_out_of_pocket | FLOAT | Patient responsibility |

### MARTS.DIM_PROVIDER
| Column | Type | Description |
|--------|------|-------------|
| provider_id | VARCHAR | Provider UUID (PK) |
| name | VARCHAR | Provider full name |
| gender | VARCHAR | M/F |
| speciality | VARCHAR | Medical specialty |
| organization_id | VARCHAR | Affiliated organization (FK) |
| address | VARCHAR | Street address |
| city | VARCHAR | City |
| state | VARCHAR | State |
| zip | VARCHAR | Zip code |
| latitude | FLOAT | Latitude |
| longitude | FLOAT | Longitude |

### MARTS.DIM_ORGANIZATION
| Column | Type | Description |
|--------|------|-------------|
| organization_id | VARCHAR | Organization UUID (PK) |
| name | VARCHAR | Organization name |
| address | VARCHAR | Street address |
| city | VARCHAR | City |
| state | VARCHAR | State |
| zip | VARCHAR | Zip code |
| latitude | FLOAT | Latitude |
| longitude | FLOAT | Longitude |
| phone | VARCHAR | Contact phone |

### MARTS.DIM_PAYER
| Column | Type | Description |
|--------|------|-------------|
| payer_id | VARCHAR | Payer UUID (PK) |
| name | VARCHAR | Insurance payer name |
| ownership | VARCHAR | Government/Private/Self-Pay |
| address | VARCHAR | Street address |
| city | VARCHAR | City |
| state | VARCHAR | State headquarters |
| zip | VARCHAR | Zip code |
| phone | VARCHAR | Contact phone |

### MARTS.DIM_DATE
| Column | Type | Description |
|--------|------|-------------|
| date_key | NUMBER | Date key in YYYYMMDD format (PK) |
| date | DATE | Calendar date |
| year | INT | Year |
| quarter | INT | Quarter (1-4) |
| quarter_name | VARCHAR | Quarter name (Q1-Q4) |
| month | INT | Month (1-12) |
| month_name | VARCHAR | Month name |
| week | INT | Week of year |
| day | INT | Day of month |
| day_of_week | INT | Day of week (0-6) |
| day_name | VARCHAR | Day name (MON-SUN) |
| is_weekend | BOOLEAN | Weekend flag |

### MARTS.DIM_ENCOUNTER_CLASS
| Column | Type | Description |
|--------|------|-------------|
| encounter_class_code | VARCHAR | Class code (PK) |
| encounter_class_description | VARCHAR | Class description |
| encounter_class_friendly_name | VARCHAR | Human-readable name |
| is_acute_care | BOOLEAN | Acute care flag |

### MARTS.FCT_ENCOUNTERS
| Column | Type | Description |
|--------|------|-------------|
| encounter_id | VARCHAR | Encounter UUID (PK) |
| patient_id | VARCHAR | Patient UUID (FK → DIM_PATIENTS) |
| provider_id | VARCHAR | Provider UUID (FK → DIM_PROVIDER) |
| organization_id | VARCHAR | Facility UUID (FK → DIM_ORGANIZATION) |
| payer_id | VARCHAR | Payer UUID (FK → DIM_PAYER) |
| start_date_key | NUMBER | Start date key (FK → DIM_DATE) |
| end_date_key | NUMBER | End date key (FK → DIM_DATE) |
| encounter_class | VARCHAR | Visit type (FK → DIM_ENCOUNTER_CLASS) |
| code | VARCHAR | Encounter type code |
| description | VARCHAR | Encounter description |
| reason_code | VARCHAR | Reason for visit code |
| reason_description | VARCHAR | Reason description |
| encounter_start_datetime | TIMESTAMP | Start date/time |
| encounter_end_datetime | TIMESTAMP | End date/time |
| encounter_duration_hours | INT | Duration in hours |
| encounter_duration_days | INT | Duration in days |
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

### Encounter Volume by Type with Dimensions
```sql
SELECT 
    ec.encounter_class_friendly_name,
    COUNT(DISTINCT e.encounter_id) as encounter_count,
    COUNT(DISTINCT e.patient_id) as unique_patients,
    AVG(e.total_claim_cost) as avg_cost,
    SUM(e.total_claim_cost) as total_cost
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_ENCOUNTER_CLASS ec
    ON e.encounter_class = ec.encounter_class_code
GROUP BY ec.encounter_class_friendly_name
ORDER BY encounter_count DESC;
```

### Monthly Encounter Trends
```sql
SELECT 
    d.year,
    d.month_name,
    d.quarter_name,
    COUNT(*) as encounter_count,
    SUM(e.total_claim_cost) as total_revenue
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_DATE d
    ON e.start_date_key = d.date_key
WHERE d.year = 2026
GROUP BY d.year, d.month, d.month_name, d.quarter_name
ORDER BY d.month;
```

### Provider Performance
```sql
SELECT 
    p.name as provider_name,
    p.speciality,
    o.name as organization_name,
    COUNT(DISTINCT e.encounter_id) as total_encounters,
    COUNT(DISTINCT e.patient_id) as unique_patients,
    SUM(e.total_claim_cost) as total_revenue
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_PROVIDER p
    ON e.provider_id = p.provider_id
JOIN SYNTHEA.MARTS.DIM_ORGANIZATION o
    ON e.organization_id = o.organization_id
GROUP BY p.name, p.speciality, o.name
ORDER BY total_revenue DESC
LIMIT 20;
```

### Payer Analysis
```sql
SELECT 
    py.name as payer_name,
    py.ownership,
    COUNT(DISTINCT e.encounter_id) as encounter_count,
    SUM(e.total_claim_cost) as total_billed,
    SUM(e.payer_coverage) as total_paid,
    SUM(e.patient_responsibility) as patient_responsibility,
    ROUND(SUM(e.payer_coverage) / NULLIF(SUM(e.total_claim_cost), 0) * 100, 2) as coverage_percentage
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_PAYER py
    ON e.payer_id = py.payer_id
GROUP BY py.name, py.ownership
ORDER BY total_billed DESC;
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

### Patient Visit History with Full Context
```sql
SELECT 
    p.full_name,
    e.encounter_start_datetime,
    ec.encounter_class_friendly_name,
    e.description,
    pr.name as provider_name,
    pr.speciality,
    o.name as facility_name,
    py.name as insurance_name,
    e.total_claim_cost,
    e.payer_coverage,
    e.patient_responsibility
FROM SYNTHEA.MARTS.FCT_ENCOUNTERS e
JOIN SYNTHEA.MARTS.DIM_PATIENTS p
    ON e.patient_id = p.patient_id
JOIN SYNTHEA.MARTS.DIM_PROVIDER pr
    ON e.provider_id = pr.provider_id
JOIN SYNTHEA.MARTS.DIM_ORGANIZATION o
    ON e.organization_id = o.organization_id
JOIN SYNTHEA.MARTS.DIM_PAYER py
    ON e.payer_id = py.payer_id
JOIN SYNTHEA.MARTS.DIM_ENCOUNTER_CLASS ec
    ON e.encounter_class = ec.encounter_class_code
WHERE p.patient_id = '<PATIENT_UUID>'
ORDER BY e.encounter_start_datetime DESC;
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
