# End-to-End Healthcare Analytics Platform
## AI-Powered FHIR Data Pipeline with Real-Time Intelligence

A modern, cloud-native healthcare data platform that orchestrates synthetic patient data generation, automated ETL/ELT workflows, data warehouse analytics, and AI-driven insights. Built with Apache Airflow, AWS S3, Snowflake, dbt, and Model Context Protocol (MCP) integration.

### 🎯 Executive Summary

This platform demonstrates a complete healthcare data analytics solution using FHIR R4 standards, combining:
- **Automated Data Generation**: Continuous synthetic patient data creation using Synthea
- **Cloud Data Lake**: Persistent storage in AWS S3 with lifecycle management  
- **Enterprise Data Warehouse**: Snowflake-based analytics platform
- **Modern Data Transformation**: dbt-powered ELT with 28+ analytics models
- **AI Integration**: MCP server enabling natural language interaction with data pipelines

## 🏗️ Architecture

- **Apache Airflow 2.10.4**: Workflow orchestration with LocalExecutor
- **PostgreSQL 13**: Airflow metadata database
- **Synthea**: Synthetic health data generator (Java-based)
- **FHIR R4**: Healthcare data format with US Core profiles
- **AWS S3**: Persistent storage for FHIR bundles
- **Snowflake**: Cloud data warehouse for analytics
- **dbt**: Data transformation and modeling
- **MCP Server**: AI assistant integration for dbt operations

## 📋 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- 8GB+ RAM recommended
- 10GB+ free disk space

## 🚀 Quick Start

### 1. Start the Services

```bash
cd /home/shiva/repos/hapi-server
docker-compose up --build -d
```

This will:
- Build the custom Airflow image with Java and Synthea
- Initialize the PostgreSQL database
- Create an admin user (username: `admin`, password: `admin`)
- Start the Airflow webserver and scheduler

### 2. Access the Airflow UI

Open your browser and navigate to:
```
http://localhost:8080
```

Login credentials:
- **Username**: `admin`
- **Password**: `admin`

### 3. Monitor the DAG

The `synthea_patient_generation` DAG should be visible and running automatically. You can:
- View DAG runs in the Grid view
- Check task logs for detailed execution information
- Monitor generated patient data

### 4. View Generated Data

Generated FHIR bundles are stored in:
```
./output/bundles/YYYY-MM-DD/HHMMSS_{patient_id}.json
```

Example:
```bash
ls -la output/bundles/2025-12-31/
```

## 📂 Project Structure

```
hapi-server/
├── docker-compose.yml          # Multi-service orchestration
├── Dockerfile                  # Custom Airflow image with Java + Synthea
├── requirements.txt            # Python dependencies
├── .env                        # Environment configuration
├── .dockerignore              # Docker build exclusions
├── dags/                       # Airflow DAG definitions
│   └── synthea_generation_dag.py
├── logs/                       # Airflow task logs (created at runtime)
├── plugins/                    # Custom Airflow plugins (optional)
└── output/                     # Generated FHIR bundles (created at runtime)
    └── bundles/
        └── YYYY-MM-DD/
            └── HHMMSS_{patient_id}.json
```

## 🔧 DAG Configuration

### Schedule
- **Frequency**: Every 10 seconds
- **Schedule Interval**: `*/10 * * * *` (cron format)
- **Max Active Runs**: 1 (sequential execution)

### Tasks

1. **generate_patient**: Executes Synthea JAR with unique seed
2. **extract_and_store_bundle**: Saves FHIR bundle to organized directory
3. **cleanup_old_bundles**: Removes bundles older than 24 hours
4. **log_generation_summary**: Logs patient demographics

### Error Handling
- **Retries**: 2 attempts per task
- **Retry Delay**: 30 seconds
- **Timeout**: 5 minutes per task
- **Cleanup**: Runs even if upstream tasks fail

## 📊 Viewing Logs

### Airflow Scheduler Logs
```bash
docker-compose logs -f airflow-scheduler
```

### Airflow Webserver Logs
```bash
docker-compose logs -f airflow-webserver
```

### PostgreSQL Logs
```bash
docker-compose logs -f postgres
```

### Task-Specific Logs
View in Airflow UI: DAG → Task Instance → Logs

## 🛠️ Common Operations

### Stop Services
```bash
docker-compose down
```

### Stop and Remove All Data (including database)
```bash
docker-compose down -v
```

### Restart Services
```bash
docker-compose restart
```

### Rebuild After Code Changes
```bash
docker-compose up --build -d
```

### View Service Status
```bash
docker-compose ps
```

### Execute Commands in Airflow Container
```bash
docker-compose exec airflow-scheduler bash
```

## 🐛 Troubleshooting

### Port 8080 Already in Use
If port 8080 is already occupied:
1. Edit `docker-compose.yml`
2. Change `"8080:8080"` to `"8081:8080"` (or another free port)
3. Restart: `docker-compose up -d`

### Permission Errors
If you encounter permission errors with volumes:
```bash
# Set correct ownership
sudo chown -R $USER:$USER logs/ output/ plugins/ dags/

# Or use the Airflow UID
sudo chown -R 50000:50000 logs/ output/ plugins/ dags/
```

### Synthea Generation Timeout
If Synthea takes too long:
1. Check available RAM (needs ~2GB free)
2. Review scheduler logs: `docker-compose logs airflow-scheduler`
3. Increase timeout in `dags/synthea_generation_dag.py` if needed

### DAG Not Appearing
If the DAG doesn't appear in the UI:
1. Check DAG file for syntax errors: `docker-compose exec airflow-scheduler airflow dags list`
2. View scheduler logs: `docker-compose logs -f airflow-scheduler`
3. Verify file is in `dags/` directory

### PostgreSQL Connection Issues
```bash
# Check postgres health
docker-compose ps postgres

# Restart postgres
docker-compose restart postgres

# Check connection
docker-compose exec postgres pg_isready -U airflow
```

## 📈 Performance Considerations

### Storage
- Each bundle: ~100-200 KB
- 10-second generation: ~8,640 bundles/day
- 24-hour retention: ~850 MB - 1.7 GB

### Resource Usage (POC Settings)
- **Webserver**: 1 CPU, 2 GB RAM
- **Scheduler**: 2 CPUs, 4 GB RAM
- **PostgreSQL**: Default limits

### Scaling Recommendations
For production use:
- Increase to CeleryExecutor with Redis for distributed execution
- Add multiple worker nodes
- Use external PostgreSQL database
- Implement data archival to S3/blob storage
- Add monitoring with Prometheus/Grafana

## 🔒 Security Notes

**⚠️ This is a POC configuration - NOT production-ready!**

For production:
- Change default admin credentials
- Use secrets management (AWS Secrets Manager, Vault, etc.)
- Enable SSL/TLS for webserver
- Restrict network access with firewalls
- Use strong PostgreSQL passwords
- Enable Airflow authentication (LDAP, OAuth, etc.)

## 📚 Additional Resources

- [Synthea Wiki](https://github.com/synthetichealth/synthea/wiki)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [FHIR R4 Specification](https://hl7.org/fhir/R4/)
- [US Core Implementation Guide](https://www.hl7.org/fhir/us/core/)
- [dbt Documentation](https://docs.getdbt.com/)
- [Model Context Protocol](https://modelcontextprotocol.io/)

## 🤖 AI Assistant Integration

This project includes a **Model Context Protocol (MCP) server** that enables AI assistants to interact with the dbt project:

- Run dbt models and tests
- View compiled SQL and documentation
- Check data quality and freshness
- Explore model lineage and dependencies

See [DBT_MCP_SETUP.md](DBT_MCP_SETUP.md) for configuration details.

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Airflow scheduler logs
3. Verify Docker resource allocation
4. Check Synthea GitHub issues for generation problems

## 📝 License

This POC follows the licensing of its components:
- Apache Airflow: Apache License 2.0
- Synthea: Apache License 2.0
- PostgreSQL: PostgreSQL License

## 🎯 Next Steps

To extend this POC:
1. **Add HAPI FHIR Server**: Upload bundles to a FHIR server
2. **Implement Validation**: Add FHIR profile validation tasks
3. **Add Notifications**: Email/Slack alerts on failures
4. **Data Analytics**: Connect DBT for data transformation
5. **Dashboard**: Grafana dashboard for generation metrics
