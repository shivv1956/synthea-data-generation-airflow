# Example MCP Configuration for Various AI Clients

## Claude Desktop Configuration

**Location:** `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)

```json
{
  "mcpServers": {
    "dbt-synthea-fhir": {
      "command": "python",
      "args": [
        "/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"
      ],
      "env": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt",
        "SNOWFLAKE_ACCOUNT": "your-account.us-east-1",
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

## Cursor/VS Code Configuration

**Location:** `.cursor/mcp_config.json` or `.vscode/mcp_config.json`

```json
{
  "servers": {
    "dbt-synthea-fhir": {
      "command": "python",
      "args": [
        "/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"
      ],
      "env": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt"
      }
    }
  }
}
```

## Zed Editor Configuration

**Location:** `~/.config/zed/settings.json`

```json
{
  "context_servers": {
    "dbt-synthea-fhir": {
      "command": {
        "path": "python",
        "args": [
          "/home/shiva/repos/synthea-data-generation-airflow/mcp/server.py"
        ]
      },
      "settings": {
        "DBT_PROJECT_DIR": "/opt/airflow/dbt",
        "DBT_PROFILES_DIR": "/opt/airflow/dbt"
      }
    }
  }
}
```

## Docker Compose MCP Service

Add to `docker-compose.yml`:

```yaml
  mcp-server:
    <<: *airflow-common
    command: python /opt/airflow/mcp/server.py
    container_name: dbt-mcp-server
    restart: unless-stopped
    environment:
      <<: *airflow-common-env
      DBT_PROJECT_DIR: /opt/airflow/dbt
      DBT_PROFILES_DIR: /opt/airflow/dbt
    depends_on:
      - airflow-webserver
    volumes:
      - ./mcp:/opt/airflow/mcp
      - ./dbt:/opt/airflow/dbt
```

## Environment Variables

Create `.env.mcp` for local development:

```bash
# DBT Configuration
DBT_PROJECT_DIR=/opt/airflow/dbt
DBT_PROFILES_DIR=/opt/airflow/dbt

# Snowflake Connection
SNOWFLAKE_ACCOUNT=your-account.us-east-1
SNOWFLAKE_USER=your-user
SNOWFLAKE_PASSWORD=your-password
SNOWFLAKE_DATABASE=SYNTHEA
SNOWFLAKE_WAREHOUSE=COMPUTE_WH
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=TRANSFORMER
```

Load with:
```bash
source .env.mcp
python mcp/server.py
```

## Testing the Configuration

### 1. Test MCP Server Directly

```bash
cd mcp/
python server.py
```

Expected output:
```
INFO:dbt-mcp-server:Server initialized
```

### 2. Test dbt Connection

```bash
export DBT_PROJECT_DIR=/opt/airflow/dbt
export DBT_PROFILES_DIR=/opt/airflow/dbt
dbt debug --project-dir $DBT_PROJECT_DIR --profiles-dir $DBT_PROFILES_DIR
```

### 3. Test in AI Client

Ask your AI assistant:
- "Can you check if dbt is working?"
- "List all models in the dbt project"
- "Run the staging models"

## Troubleshooting

### Server Won't Start

**Issue:** `ModuleNotFoundError: No module named 'mcp'`

**Solution:**
```bash
pip install mcp>=0.9.0
```

### Connection Failed

**Issue:** `Could not connect to Snowflake`

**Check:**
```bash
# Verify credentials
echo $SNOWFLAKE_ACCOUNT
echo $SNOWFLAKE_USER

# Test dbt connection
dbt debug
```

### Permission Denied

**Issue:** `Permission denied: 'server.py'`

**Solution:**
```bash
chmod +x mcp/server.py
```

### Path Issues

**Issue:** `dbt: command not found`

**Solution:**
```bash
# Add dbt to PATH
export PATH="$PATH:$HOME/.local/bin"

# Or install globally
pip install --user dbt-core dbt-snowflake
```

## Security Best Practices

### 1. Never Commit Credentials

Add to `.gitignore`:
```
.env.mcp
**/mcp_config.json
claude_desktop_config.json
```

### 2. Use Environment Variables

Instead of hardcoding in config:
```json
"env": {
  "SNOWFLAKE_PASSWORD": "${SNOWFLAKE_PASSWORD}"
}
```

### 3. Restrict Permissions

```bash
chmod 600 ~/.config/Claude/claude_desktop_config.json
chmod 600 .env.mcp
```

### 4. Use Read-Only Role

Create a read-only Snowflake role for MCP:
```sql
CREATE ROLE MCP_READER;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE MCP_READER;
GRANT USAGE ON DATABASE SYNTHEA TO ROLE MCP_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA SYNTHEA.RAW TO ROLE MCP_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA SYNTHEA.STAGING TO ROLE MCP_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA SYNTHEA.MARTS TO ROLE MCP_READER;
```

Then use in config:
```bash
SNOWFLAKE_ROLE=MCP_READER
```

## Advanced Configuration

### Custom Timeout

Edit `mcp/server.py`:
```python
# Increase timeout for long-running models
result = await run_dbt_command("run", *args, timeout=600)  # 10 minutes
```

### Logging

Enable debug logging:
```python
# In server.py
logging.basicConfig(level=logging.DEBUG)
```

### Multiple Environments

Create separate configs for dev/prod:
```json
{
  "mcpServers": {
    "dbt-synthea-dev": {
      "command": "python",
      "args": ["./mcp/server.py"],
      "env": {
        "DBT_TARGET": "dev",
        "SNOWFLAKE_DATABASE": "SYNTHEA_DEV"
      }
    },
    "dbt-synthea-prod": {
      "command": "python",
      "args": ["./mcp/server.py"],
      "env": {
        "DBT_TARGET": "prod",
        "SNOWFLAKE_DATABASE": "SYNTHEA_PROD"
      }
    }
  }
}
```

## Quick Reference

### Common dbt Commands via MCP

| Query | MCP Tool | dbt Command |
|-------|----------|-------------|
| "Run staging models" | `dbt_run` | `dbt run --select tag:staging` |
| "Test all models" | `dbt_test` | `dbt test` |
| "Show SQL for stg_patients" | `get_model_sql` | Reads compiled SQL |
| "Generate docs" | `dbt_docs_generate` | `dbt docs generate` |
| "List all models" | `dbt_list` | `dbt list --resource-type model` |
| "Check connection" | `dbt_debug` | `dbt debug` |
| "Check source freshness" | `dbt_source_freshness` | `dbt source freshness` |

### File Locations

- Server: `mcp/server.py`
- Config: `mcp/pyproject.toml`
- Tests: `mcp/tests/test_server.py`
- Docs: `mcp/README.md`
- Setup Guide: `DBT_MCP_SETUP.md`
