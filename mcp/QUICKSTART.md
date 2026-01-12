# 🚀 Quick Reference: DBT MCP Integration

## What Was Added

### New Files
```
mcp/
├── server.py                      # MCP server implementation (11 tools)
├── __init__.py                    # Package initialization
├── pyproject.toml                 # Python project configuration
├── package.json                   # Node.js metadata
├── README.md                      # MCP server documentation
├── CONFIGURATION_EXAMPLES.md      # Client configuration examples
├── start_mcp.sh                   # Quick start script
├── .gitignore                     # Ignore patterns
└── tests/
    └── test_server.py            # Unit tests
```

### Documentation
- `DBT_MCP_SETUP.md` - Complete setup guide
- Updated `README.md` - Added MCP section
- Updated `requirements.txt` - Added MCP dependency
- Updated `docker-compose.yml` - Added MCP volume mount

## Quick Start

### 1. Install Dependencies

```bash
pip install mcp>=0.9.0
```

### 2. Configure Environment

```bash
export DBT_PROJECT_DIR="/opt/airflow/dbt"
export DBT_PROFILES_DIR="/opt/airflow/dbt"
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export SNOWFLAKE_PASSWORD="your-password"
```

### 3. Test Server

```bash
cd mcp/
python server.py
```

### 4. Configure AI Client

Add to Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

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
        "SNOWFLAKE_PASSWORD": "your-password"
      }
    }
  }
}
```

## Available Tools

| Tool | Purpose | Example Query |
|------|---------|---------------|
| `dbt_run` | Execute models | "Run staging models" |
| `dbt_test` | Run tests | "Test dim_patients" |
| `dbt_compile` | Generate SQL | "Compile staging models" |
| `dbt_docs_generate` | Create docs | "Generate dbt documentation" |
| `dbt_list` | List resources | "Show all models" |
| `dbt_debug` | Check setup | "Is dbt connected to Snowflake?" |
| `get_model_sql` | View SQL | "Show SQL for stg_encounters" |
| `get_run_results` | Last run stats | "What happened in last run?" |
| `get_manifest` | Model metadata | "Show lineage for fct_medications" |
| `dbt_snapshot` | Run snapshots | "Execute snapshots" |
| `dbt_source_freshness` | Check freshness | "Check source data freshness" |

## Example Queries

Once configured in your AI client, try:

- "Run all dbt staging models"
- "Test the patient dimension table"
- "Show me the compiled SQL for stg_patients"
- "What models are in the marts layer?"
- "Generate the dbt documentation"
- "Check if dbt can connect to Snowflake"
- "What was the result of the last dbt run?"
- "Show model lineage for fct_encounters"

## Docker Integration

### Access from Airflow Container

```bash
docker exec -it airflow-webserver python /opt/airflow/mcp/server.py
```

### Run Tests

```bash
docker exec -it airflow-webserver bash -c "cd /opt/airflow/mcp && pytest tests/ -v"
```

## Rebuild After Changes

```bash
# Stop containers
docker-compose down

# Rebuild with new dependencies
docker-compose build

# Start services
docker-compose up -d
```

## Architecture

```
┌─────────────┐
│ AI Assistant│ (Claude, Cursor, etc.)
└──────┬──────┘
       │ MCP Protocol
       ▼
┌─────────────┐
│ MCP Server  │ (Python)
│ 11 Tools    │
└──────┬──────┘
       │
   ┌───┴───┐
   ▼       ▼
┌─────┐ ┌──────────┐
│ dbt │→│Snowflake │
└─────┘ └──────────┘
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Server won't start | `pip install mcp>=0.9.0` |
| dbt not found | `pip install dbt-core dbt-snowflake` |
| Connection error | Check Snowflake credentials |
| Permission denied | `chmod +x mcp/start_mcp.sh` |
| Module errors | Rebuild Docker: `docker-compose build` |

## Next Steps

1. ✅ Test server: `python mcp/server.py`
2. ✅ Configure AI client (Claude Desktop recommended)
3. ✅ Try example queries
4. ✅ Review logs: `tail -f logs/mcp-server.log`
5. ✅ Read full docs: `DBT_MCP_SETUP.md`

## Documentation

- [DBT_MCP_SETUP.md](../DBT_MCP_SETUP.md) - Complete setup guide
- [mcp/README.md](README.md) - MCP server documentation  
- [mcp/CONFIGURATION_EXAMPLES.md](CONFIGURATION_EXAMPLES.md) - Client configs
- [DBT_SETUP_GUIDE.md](../DBT_SETUP_GUIDE.md) - dbt setup

## Security

⚠️ **Important:**
- Never commit credentials to git
- Use environment variables
- Restrict config file permissions: `chmod 600`
- Consider using a read-only Snowflake role

## Support

Questions? Check:
1. `mcp/README.md` - Basic usage
2. `DBT_MCP_SETUP.md` - Detailed setup
3. dbt logs: `dbt/logs/`
4. MCP logs: Enable debug logging in `server.py`
