# Custom Airflow 2.10.4 Dockerfile with Java Runtime and Synthea
# This image extends the official Apache Airflow image to include:
# - Java 11 runtime (required for Synthea JAR execution)
# - Synthea synthetic health data generator
# - FHIR resources Python library for data validation

FROM apache/airflow:2.10.4-python3.11

# Switch to root user to install system packages
USER root

# Install Java Runtime Environment and utilities
# - default-jre: Java 11 runtime for executing Synthea JAR
# - curl: for downloading Synthea JAR from GitHub releases
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        default-jre \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create Synthea directory and set permissions
RUN mkdir -p /opt/synthea/output && \
    chown -R airflow:root /opt/synthea && \
    chmod -R 775 /opt/synthea

# Download Synthea JAR from official GitHub releases
# Using master-branch-latest for most up-to-date synthetic data generation
RUN curl -L \
    "https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar" \
    -o "/opt/synthea/synthea-with-dependencies.jar" && \
    chmod 644 /opt/synthea/synthea-with-dependencies.jar

# Switch back to airflow user for security best practices
USER airflow

# Copy and install Python requirements
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# Set working directory
WORKDIR /opt/airflow

# Health check for Airflow services (overridden by docker-compose)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl --fail http://localhost:8080/health || exit 1
