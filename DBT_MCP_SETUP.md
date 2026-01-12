# DBT Model Context Protocol (MCP) Server Setup Guide

## What is MCP?

Model Context Protocol (MCP) is an open protocol that enables AI assistants to securely connect to external tools and data sources. This implementation provides a dbt-specific MCP server that allows AI assistants to interact with your Synthea FHIR analytics pipeline.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   AI Assistant (Claude, etc.)               │
└────────────────────────┬────────────────────────────────────┘
                         │ MCP Protocol
                         ▼
┌─────────────────────────────────────────────────────────────┐
│               DBT MCP Server (Python)                       │
│  - dbt_run, dbt_test, dbt_compile                          │
│  - get_model_sql, get_manifest, get_run_results           │
│  - dbt_docs_generate, dbt_list, dbt_debug                 │
└────────────────────────┬────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
    ┌──────────────┐      ┌──────────────┐
    │   DBT Core   │      │  Snowflake   │
    │              │─────▶│   Database   │
    └──────────────┘      └──────────────┘
```

## Features

### 🔧 Available Tools

| Tool | Description | Use Case |
|------|-------------|----------|
| `dbt_run` | Execute dbt models | Run staging, intermediate, or marts models |
| `dbt_test` | Run data quality tests | Validate data integrity |
| `dbt_compile` | Compile to SQL | Preview generated queries |
| `dbt_docs_generate` | Generate documentation | Create project docs |
| `dbt_list` | List resources | Discover models, tests, sources |
| `dbt_debug` | Check configuration | Troubleshoot connection issues |
| `get_model_sql` | View model SQL | Inspect compiled queries |
| `get_run_results` | View execution stats | Analyze last run performance |
| `get_manifest` | Access metadata | Explore model lineage |
| `dbt_snapshot` | Run snapshots | Track historical changes |
| `dbt_source_freshness` | Check data age | Monitor data freshness |

## Installation

### Step 1: Install MCP Dependencies

Add to [requirements.txt](../requirements.txt):

```bash
# Model Context Protocol for AI integration
mcp>=0.9.0
```

Or install directly:

```bash
pip install mcp>=0.9.0
```

### Step 2: Configure Environment

The server needs access to dbt and Snowflake. Set these environment variables:

```bash
# DBT Configuration
export DBT_PROJECT_DIR="/opt/airflow/dbt"
export DBT_PROFILES_DIR="/opt/airflow/dbt"

# Snowflake Credentials (already configured in docker-compose.yml)
export SNOWFLAKE_ACCOUNT="your-account.region"
export SNOWFLAKE_USER="your-user"
export SNOWFLAKE_PASSWORD="your-password"
export SNOWFLAKE_DATABASE="SYNTHEA"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
export SNOWFLAKE_SCHEMA="RAW"
export SNOWFLAKE_ROLE="TRANSFORMER"
```

### Step 3: Test the Server

```bash
cd mcp/
python server.py
```

The server will start and listen for MCP protocol messages on stdin/stdout.

## Client Configuration

### Claude Desktop

1. **Locate configuration file:**
   - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
   - Linux: `~/.config/Claude/claude_desktop_config.json`

2. **Add server configuration:**

```json
{
  "mcpServers": {
    "dbt-synthea-fhir": {
      "command": "python",
      "args": ["/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"],
      "env": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt",
        "SNOWFLAKE_ACCOUNT": "${SNOWFLAKE_ACCOUNT}",
        "SNOWFLAKE_USER": "${SNOWFLAKE_USER}",
        "SNOWFLAKE_PASSWORD": "${SNOWFLAKE_PASSWORD}",
        "SNOWFLAKE_DATABASE": "SYNTHEA",
        "SNOWFLAKE_WAREHOUSE": "COMPUTE_WH",
        "SNOWFLAKE_SCHEMA": "RAW",
        "SNOWFLAKE_ROLE": "TRANSFORMER"
      }
    }
  }
}
```

3. **Restart Claude Desktop**

### Cursor / VS Code with Cline/Copilot

Create `.cursor/mcp_config.json` or `.vscode/mcp_config.json`:

```json
{
  "servers": {
    "dbt-synthea-fhir": {
      "command": "python",
      "args": ["/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"],
      "env": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt"
      }
    }
  }
}
```

### Zed Editor

Add to `~/.config/zed/settings.json`:

```json
{
  "context_servers": {
    "dbt-synthea-fhir": {
      "command": {
        "path": "python",
        "args": ["/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"]
      },
      "settings": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt"
      }
    }
  }
}
```

## Usage Examples

Once configured, you can interact with your dbt project through natural language:

### Running Models

**You:** "Run all staging models in dbt"
- Server executes: `dbt run --select tag:staging`

**You:** "Run the patient dimension model with full refresh"
- Server executes: `dbt run --models dim_patients --full-refresh`

**You:** "Run models in the marts layer"
- Server executes: `dbt run --select tag:marts`

### Testing

**You:** "Test the staging patients model"
- Server executes: `dbt test --models stg_patients`

**You:** "Run all data quality tests"
- Server executes: `dbt test`

### Exploring Models

**You:** "Show me the SQL for stg_encounters"
- Server retrieves compiled SQL from target directory

**You:** "What models depend on stg_patients?"
- Server queries manifest for lineage information

**You:** "List all models in the intermediate layer"
- Server executes: `dbt list --resource-type model --select tag:intermediate`

### Documentation

**You:** "Generate dbt documentation"
- Server executes: `dbt docs generate`

**You:** "What's the description of dim_patients?"
- Server retrieves from manifest metadata

### Troubleshooting

**You:** "Check if dbt can connect to Snowflake"
- Server executes: `dbt debug`

**You:** "What happened in the last dbt run?"
- Server reads and parses `target/run_results.json`

## Docker Integration

### Add to Dockerfile

The MCP server is already included in the Airflow container. To explicitly add it:

```dockerfile
# Copy MCP server
COPY mcp/ /opt/airflow/mcp/

# Install MCP dependencies
RUN pip install mcp>=0.9.0
```

### Access from Container

```bash
# Execute MCP server inside Airflow container
docker exec -it airflow-webserver python /opt/airflow/mcp/server.py

# Or run interactively
docker exec -it airflow-webserver bash
cd /opt/airflow/mcp
python server.py
```

### Add as Airflow Service

You can run the MCP server as a separate service in docker-compose.yml:

```yaml
  mcp-server:
    <<: *airflow-common
    command: python /opt/airflow/mcp/server.py
    restart: unless-stopped
    depends_on:
      - airflow-webserver
    environment:
      <<: *airflow-common-env
    volumes:
      - ./mcp:/opt/airflow/mcp
      - ./dbt:/opt/airflow/dbt
```

## Security Considerations

### Credentials Management

⚠️ **Never hardcode credentials** in MCP configuration files!

**Best Practices:**

1. **Use environment variables:**
   ```json
   "env": {
     "SNOWFLAKE_PASSWORD": "${SNOWFLAKE_PASSWORD}"
   }
   ```

2. **Use secrets managers:**
   - AWS Secrets Manager
   - HashiCorp Vault
   - 1Password CLI

3. **Restrict file permissions:**
   ```bash
   chmod 600 ~/.config/Claude/claude_desktop_config.json
   ```

### Access Control

The MCP server has full access to your dbt project and Snowflake. Limit its capabilities:

1. **Use read-only Snowflake role** for query-only operations
2. **Create separate MCP role** with limited permissions
3. **Audit MCP tool usage** through logs

## Monitoring and Logging

### Enable Debug Logging

```python
# In server.py
logging.basicConfig(level=logging.DEBUG)
```

### Log MCP Requests

All dbt commands are logged with:
- Command executed
- Execution time
- Success/failure status
- Output/errors

View logs:
```bash
tail -f /opt/airflow/logs/mcp-server.log
```

## Troubleshooting

### Server Won't Start

**Error:** `ModuleNotFoundError: No module named 'mcp'`

**Solution:**
```bash
pip install mcp>=0.9.0
```

**Error:** `dbt command not found`

**Solution:**
```bash
pip install dbt-core dbt-snowflake
which dbt  # Verify installation
```

### Connection Errors

**Error:** `Could not connect to Snowflake`

**Solution:**
1. Verify credentials: `echo $SNOWFLAKE_PASSWORD`
2. Test connection: Use `dbt_debug` tool
3. Check profiles.yml: Ensure environment variables are set

### Permission Errors

**Error:** `Access Denied on SYNTHEA.STAGING`

**Solution:**
```sql
-- Grant schema access
GRANT USAGE ON SCHEMA SYNTHEA.STAGING TO ROLE TRANSFORMER;
GRANT ALL ON ALL TABLES IN SCHEMA SYNTHEA.STAGING TO ROLE TRANSFORMER;
```

### Timeout Issues

**Error:** `Command timed out after 300 seconds`

**Solution:** Increase timeout in server.py:
```python
result = await run_dbt_command("run", *args, timeout=600)  # 10 minutes
```

## Advanced Configuration

### Custom dbt Variables

Pass variables to dbt commands:

**Query:** "Run staging models for data from January 2026"

```json
{
  "tool": "dbt_run",
  "arguments": {
    "select": "tag:staging",
    "vars": {
      "start_date": "2026-01-01",
      "end_date": "2026-01-31"
    }
  }
}
```

### Incremental Runs

Control incremental behavior:

```json
{
  "tool": "dbt_run",
  "arguments": {
    "models": "stg_patients",
    "full_refresh": false
  }
}
```

### Selection Syntax

Leverage dbt's powerful selection:

- `tag:staging` - All models with staging tag
- `stg_patients+` - Model and all downstream
- `+dim_patients` - Model and all upstream
- `@stg_encounters` - Model and direct dependencies
- `marts.*` - All models in marts directory

## Performance Tips

1. **Use selective runs:** Don't run all models every time
2. **Enable threading:** Configure in profiles.yml
3. **Optimize queries:** Review compiled SQL
4. **Monitor warehouse:** Use appropriate size

## Future Enhancements

Potential additions to the MCP server:

- [ ] Streaming results for long-running commands
- [ ] Parallel model execution status
- [ ] Real-time test failure notifications
- [ ] Cost tracking and optimization suggestions
- [ ] Automated performance analysis
- [ ] Schema change detection
- [ ] Data quality scorecards

## Support

For issues or questions:
1. Check [mcp/README.md](README.md) for basic usage
2. Review dbt logs in `dbt/logs/`
3. Enable debug logging for detailed output
4. Consult dbt documentation: https://docs.getdbt.com

## References

- [Model Context Protocol Specification](https://modelcontextprotocol.io)
- [dbt Documentation](https://docs.getdbt.com)
- [Snowflake Documentation](https://docs.snowflake.com)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
