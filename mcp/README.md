# DBT MCP Server for Synthea FHIR Analytics Pipeline

This Model Context Protocol (MCP) server enables AI assistants like Claude, ChatGPT, and other MCP-compatible clients to interact with the dbt project directly.

## Features

### Available Tools

1. **dbt_run** - Run dbt models with optional filters
   - Filter by models, tags, or selection syntax
   - Support for full refresh mode
   - Pass custom variables

2. **dbt_test** - Execute data quality tests
   - Test specific models or all tests
   - View pass/fail statistics

3. **dbt_compile** - Compile models to SQL without execution
   - Preview generated SQL
   - Validate model syntax

4. **dbt_docs_generate** - Generate project documentation
   - Creates catalog, manifest, and HTML docs

5. **dbt_list** - List project resources
   - Filter by resource type (model, test, source)
   - Use dbt selection syntax

6. **dbt_debug** - Check project health
   - Verify database connection
   - Validate configuration

7. **get_model_sql** - Retrieve SQL for specific models
   - View compiled or source SQL

8. **get_run_results** - View last execution results
   - Execution statistics
   - Success/failure status

9. **get_manifest** - Access project metadata
   - Model lineage
   - Dependencies and relationships

10. **dbt_snapshot** - Run SCD Type 2 snapshots

11. **dbt_source_freshness** - Check data freshness

## Installation

### Prerequisites

- Python 3.11+
- dbt-core and dbt-snowflake installed
- Environment variables configured (see below)

### Setup

1. **Install MCP dependencies:**

```bash
cd mcp/
pip install -e .
```

2. **Configure environment variables:**

```bash
export DBT_PROJECT_DIR="/opt/airflow/dbt"
export DBT_PROFILES_DIR="/opt/airflow/dbt"
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export SNOWFLAKE_PASSWORD="your-password"
export SNOWFLAKE_DATABASE="SYNTHEA"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
export SNOWFLAKE_SCHEMA="RAW"
export SNOWFLAKE_ROLE="TRANSFORMER"
```

3. **Test the server:**

```bash
python server.py
```

## Usage

### With Claude Desktop

Add to your Claude Desktop configuration (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "dbt-synthea-fhir": {
      "command": "python",
      "args": ["/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"],
      "env": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt",
        "SNOWFLAKE_ACCOUNT": "your-account",
        "SNOWFLAKE_USER": "your-user",
        "SNOWFLAKE_PASSWORD": "your-password",
        "SNOWFLAKE_DATABASE": "SYNTHEA",
        "SNOWFLAKE_WAREHOUSE": "COMPUTE_WH",
        "SNOWFLAKE_SCHEMA": "RAW",
        "SNOWFLAKE_ROLE": "TRANSFORMER"
      }
    }
  }
}
```

### With Cursor / VS Code

Add to your `.cursor/mcp.json` or VS Code settings:

```json
{
  "dbt-synthea-fhir": {
    "command": "python",
    "args": ["/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"],
    "env": {
      "DBT_PROJECT_DIR": "/opt/airflow/dbt",
      "DBT_PROFILES_DIR": "/opt/airflow/dbt"
    }
  }
}
```

### Docker Integration

The MCP server is automatically available in the Airflow containers. Access it via:

```bash
docker exec -it airflow-webserver python /opt/airflow/mcp/server.py
```

## Example Queries

Once configured, you can ask your AI assistant:

- "Run the staging models in dbt"
- "Test the dim_patients model"
- "Show me the SQL for stg_encounters"
- "What models are in the marts layer?"
- "Check if dbt can connect to Snowflake"
- "Generate the dbt documentation"
- "What was the result of the last dbt run?"
- "Show me the lineage for fct_medications"

## Architecture

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  AI Client   │────────▶│  MCP Server  │────────▶│  DBT Core    │
│  (Claude)    │◀────────│  (Python)    │◀────────│              │
└──────────────┘         └──────────────┘         └──────────────┘
                                │                         │
                                │                         ▼
                                │                  ┌──────────────┐
                                └─────────────────▶│  Snowflake   │
                                                   │  (Database)  │
                                                   └──────────────┘
```

## Troubleshooting

### Server Won't Start

- Verify Python 3.11+ is installed: `python --version`
- Check MCP package: `pip show mcp`
- Ensure dbt is in PATH: `which dbt`

### Connection Errors

- Verify Snowflake credentials in environment
- Test connection: Use the `dbt_debug` tool
- Check profiles.yml configuration

### Permission Issues

- Ensure TRANSFORMER role has proper grants
- Verify warehouse is running
- Check schema access permissions

## Development

### Running Tests

```bash
cd mcp/
pytest tests/ -v
```

### Code Formatting

```bash
black .
ruff check .
```

### Adding New Tools

1. Add tool definition to `handle_list_tools()`
2. Implement handler in `handle_call_tool()`
3. Update documentation
4. Add tests

## License

MIT License - See project root for details
