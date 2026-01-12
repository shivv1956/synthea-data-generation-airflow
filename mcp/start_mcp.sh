#!/bin/bash
# Quick start script for DBT MCP Server

set -e

echo "🚀 Starting DBT MCP Server..."

# Check if running in Docker or local
if [ -f /.dockerenv ]; then
    echo "Running in Docker container"
    export DBT_PROJECT_DIR=/opt/airflow/dbt
    export DBT_PROFILES_DIR=/opt/airflow/dbt
else
    echo "Running locally"
    export DBT_PROJECT_DIR="$(pwd)/dbt"
    export DBT_PROFILES_DIR="$(pwd)/dbt"
fi

# Check dependencies
echo "Checking dependencies..."

if ! command -v python &> /dev/null; then
    echo "❌ Python not found. Please install Python 3.11+"
    exit 1
fi

if ! command -v dbt &> /dev/null; then
    echo "❌ dbt not found. Installing..."
    pip install dbt-core dbt-snowflake
fi

if ! python -c "import mcp" 2>/dev/null; then
    echo "❌ MCP package not found. Installing..."
    pip install mcp
fi

echo "✅ All dependencies installed"

# Check environment variables
if [ -z "$SNOWFLAKE_ACCOUNT" ]; then
    echo "⚠️  Warning: SNOWFLAKE_ACCOUNT not set"
    echo "Set environment variables or the server may fail to connect"
fi

# Start the server
echo "Starting MCP server..."
cd "$(dirname "$0")"
exec python server.py
