"""
DBT MCP Server for Synthea FHIR Analytics Pipeline

This Model Context Protocol (MCP) server enables AI assistants to interact with
the dbt project, including:
- Running dbt models (staging, intermediate, marts)
- Executing data quality tests
- Compiling and previewing SQL
- Viewing model documentation and lineage
- Checking dbt project status

Author: Synthea Data Pipeline Team
Version: 1.0.0
"""

import asyncio
import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

import mcp.server.stdio
import mcp.types as types
from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("dbt-mcp-server")

# DBT project configuration
DBT_PROJECT_DIR = os.getenv("DBT_PROJECT_DIR", "/opt/airflow/dbt")
DBT_PROFILES_DIR = os.getenv("DBT_PROFILES_DIR", "/opt/airflow/dbt")

# Initialize MCP server
server = Server("dbt-synthea-fhir")


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """
    List all available DBT tools for the MCP client.
    """
    return [
        types.Tool(
            name="dbt_run",
            description="Run dbt models with optional filters (models, tags, or full refresh)",
            inputSchema={
                "type": "object",
                "properties": {
                    "models": {
                        "type": "string",
                        "description": "Specific models to run (e.g., 'stg_patients' or 'staging.*')",
                    },
                    "select": {
                        "type": "string",
                        "description": "dbt selection syntax (e.g., 'tag:staging' or 'marts+')",
                    },
                    "full_refresh": {
                        "type": "boolean",
                        "description": "Force full refresh of incremental models",
                        "default": False,
                    },
                    "vars": {
                        "type": "object",
                        "description": "Variables to pass to dbt (e.g., {'start_date': '2026-01-01'})",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_test",
            description="Run dbt tests with optional filters",
            inputSchema={
                "type": "object",
                "properties": {
                    "models": {
                        "type": "string",
                        "description": "Test specific models (e.g., 'stg_patients')",
                    },
                    "select": {
                        "type": "string",
                        "description": "dbt selection syntax for tests",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_compile",
            description="Compile dbt models to view generated SQL without running",
            inputSchema={
                "type": "object",
                "properties": {
                    "models": {
                        "type": "string",
                        "description": "Models to compile",
                    },
                    "select": {
                        "type": "string",
                        "description": "dbt selection syntax",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_docs_generate",
            description="Generate dbt documentation (catalog and manifest)",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="dbt_list",
            description="List dbt resources (models, tests, sources)",
            inputSchema={
                "type": "object",
                "properties": {
                    "resource_type": {
                        "type": "string",
                        "description": "Resource type to list: 'model', 'test', 'source', 'snapshot'",
                        "enum": ["model", "test", "source", "snapshot", "all"],
                        "default": "all",
                    },
                    "select": {
                        "type": "string",
                        "description": "dbt selection syntax",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_debug",
            description="Check dbt project configuration and database connection",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_model_sql",
            description="Get the compiled SQL for a specific dbt model",
            inputSchema={
                "type": "object",
                "properties": {
                    "model_name": {
                        "type": "string",
                        "description": "Name of the dbt model (e.g., 'stg_patients')",
                    },
                },
                "required": ["model_name"],
            },
        ),
        types.Tool(
            name="get_run_results",
            description="Get the last dbt run results with execution statistics",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_manifest",
            description="Get dbt project manifest with model metadata and lineage",
            inputSchema={
                "type": "object",
                "properties": {
                    "model_name": {
                        "type": "string",
                        "description": "Optional: Get details for a specific model",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_snapshot",
            description="Run dbt snapshots for SCD Type 2 tracking",
            inputSchema={
                "type": "object",
                "properties": {
                    "select": {
                        "type": "string",
                        "description": "Snapshot selection",
                    },
                },
            },
        ),
        types.Tool(
            name="dbt_source_freshness",
            description="Check source data freshness",
            inputSchema={
                "type": "object",
                "properties": {
                    "select": {
                        "type": "string",
                        "description": "Source selection",
                    },
                },
            },
        ),
    ]


async def run_dbt_command(
    command: str, *args: str, timeout: int = 300
) -> Dict[str, Any]:
    """
    Execute a dbt command and return results.

    Args:
        command: dbt subcommand (run, test, compile, etc.)
        args: Additional command arguments
        timeout: Command timeout in seconds

    Returns:
        Dict with stdout, stderr, return_code, and parsed results
    """
    cmd = ["dbt", command, "--project-dir", DBT_PROJECT_DIR, "--profiles-dir", DBT_PROFILES_DIR]
    cmd.extend(args)

    logger.info(f"Executing command: {' '.join(cmd)}")

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=DBT_PROJECT_DIR,
        )

        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)

        return {
            "command": " ".join(cmd),
            "return_code": process.returncode,
            "stdout": stdout.decode("utf-8"),
            "stderr": stderr.decode("utf-8"),
            "success": process.returncode == 0,
        }

    except asyncio.TimeoutError:
        logger.error(f"Command timed out after {timeout} seconds")
        return {
            "command": " ".join(cmd),
            "return_code": -1,
            "stdout": "",
            "stderr": f"Command timed out after {timeout} seconds",
            "success": False,
        }
    except Exception as e:
        logger.error(f"Error executing command: {str(e)}")
        return {
            "command": " ".join(cmd),
            "return_code": -1,
            "stdout": "",
            "stderr": str(e),
            "success": False,
        }


@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """
    Handle tool execution requests from MCP clients.
    """
    arguments = arguments or {}

    try:
        if name == "dbt_run":
            args = []
            if arguments.get("models"):
                args.extend(["--models", arguments["models"]])
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])
            if arguments.get("full_refresh"):
                args.append("--full-refresh")
            if arguments.get("vars"):
                args.extend(["--vars", json.dumps(arguments["vars"])])

            result = await run_dbt_command("run", *args)

            # Parse run results if available
            run_results = get_file_content(Path(DBT_PROJECT_DIR) / "target" / "run_results.json")
            
            response = f"**DBT Run Results**\n\n"
            response += f"Success: {result['success']}\n\n"
            
            if run_results:
                results = json.loads(run_results)
                response += f"Models executed: {len(results.get('results', []))}\n"
                response += f"Elapsed time: {results.get('elapsed_time', 0):.2f}s\n\n"
                
                for model_result in results.get('results', []):
                    status = model_result.get('status', 'unknown')
                    node_name = model_result.get('unique_id', '').split('.')[-1]
                    response += f"- {node_name}: {status}\n"
            
            response += f"\n**Output:**\n```\n{result['stdout'][-1000:]}\n```"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_test":
            args = []
            if arguments.get("models"):
                args.extend(["--models", arguments["models"]])
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])

            result = await run_dbt_command("test", *args)

            # Parse test results
            run_results = get_file_content(Path(DBT_PROJECT_DIR) / "target" / "run_results.json")
            
            response = f"**DBT Test Results**\n\n"
            response += f"Success: {result['success']}\n\n"
            
            if run_results:
                results = json.loads(run_results)
                test_results = results.get('results', [])
                passed = sum(1 for r in test_results if r.get('status') == 'pass')
                failed = sum(1 for r in test_results if r.get('status') in ['fail', 'error'])
                
                response += f"Total tests: {len(test_results)}\n"
                response += f"✓ Passed: {passed}\n"
                response += f"✗ Failed: {failed}\n\n"
                
                if failed > 0:
                    response += "**Failed Tests:**\n"
                    for test_result in test_results:
                        if test_result.get('status') in ['fail', 'error']:
                            response += f"- {test_result.get('unique_id', 'unknown')}\n"
            
            response += f"\n**Output:**\n```\n{result['stdout'][-1000:]}\n```"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_compile":
            args = []
            if arguments.get("models"):
                args.extend(["--models", arguments["models"]])
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])

            result = await run_dbt_command("compile", *args)
            
            response = f"**DBT Compile Results**\n\n"
            response += f"Success: {result['success']}\n\n"
            response += f"Compiled models available in: `{DBT_PROJECT_DIR}/target/compiled/`\n\n"
            response += f"```\n{result['stdout'][-1000:]}\n```"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_docs_generate":
            result = await run_dbt_command("docs", "generate")
            
            response = f"**DBT Documentation Generated**\n\n"
            response += f"Success: {result['success']}\n\n"
            response += f"Documentation files:\n"
            response += f"- Catalog: `{DBT_PROJECT_DIR}/target/catalog.json`\n"
            response += f"- Manifest: `{DBT_PROJECT_DIR}/target/manifest.json`\n"
            response += f"- Index: `{DBT_PROJECT_DIR}/target/index.html`\n\n"
            response += f"Run `dbt docs serve` to view in browser.\n"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_list":
            args = []
            resource_type = arguments.get("resource_type", "all")
            if resource_type != "all":
                args.extend(["--resource-type", resource_type])
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])

            result = await run_dbt_command("list", *args)
            
            response = f"**DBT Resources**\n\n"
            if result['success']:
                resources = result['stdout'].strip().split('\n')
                response += f"Found {len(resources)} resources:\n\n"
                for resource in resources[:50]:  # Limit to first 50
                    response += f"- {resource}\n"
                if len(resources) > 50:
                    response += f"\n... and {len(resources) - 50} more\n"
            else:
                response += f"Error: {result['stderr']}\n"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_debug":
            result = await run_dbt_command("debug")
            
            response = f"**DBT Debug Information**\n\n"
            response += f"```\n{result['stdout']}\n```\n"
            
            if not result['success']:
                response += f"\n**Errors:**\n```\n{result['stderr']}\n```"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "get_model_sql":
            model_name = arguments.get("model_name")
            if not model_name:
                return [types.TextContent(type="text", text="Error: model_name is required")]

            # Try to find compiled SQL
            compiled_path = Path(DBT_PROJECT_DIR) / "target" / "compiled" / "synthea_fhir" / "models"
            sql_files = list(compiled_path.rglob(f"{model_name}.sql"))
            
            if sql_files:
                sql_content = sql_files[0].read_text()
                response = f"**Compiled SQL for {model_name}**\n\n```sql\n{sql_content}\n```"
            else:
                # Try to find source SQL
                models_path = Path(DBT_PROJECT_DIR) / "models"
                sql_files = list(models_path.rglob(f"{model_name}.sql"))
                
                if sql_files:
                    sql_content = sql_files[0].read_text()
                    response = f"**Source SQL for {model_name}**\n\n```sql\n{sql_content}\n```\n\n"
                    response += "*Note: This is the source SQL. Run dbt compile to see the compiled version.*"
                else:
                    response = f"Error: Model '{model_name}' not found in project"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "get_run_results":
            run_results_path = Path(DBT_PROJECT_DIR) / "target" / "run_results.json"
            
            if not run_results_path.exists():
                return [types.TextContent(
                    type="text",
                    text="No run results found. Execute a dbt command first (run, test, etc.)"
                )]
            
            content = run_results_path.read_text()
            results = json.loads(content)
            
            response = f"**Last DBT Run Results**\n\n"
            response += f"Generated at: {results.get('generated_at', 'unknown')}\n"
            response += f"Elapsed time: {results.get('elapsed_time', 0):.2f}s\n"
            response += f"Success: {results['metadata'].get('dbt_schema_version') is not None}\n\n"
            
            results_list = results.get('results', [])
            response += f"**Executed Nodes:** {len(results_list)}\n\n"
            
            for result in results_list[:20]:  # Limit to 20
                node_id = result.get('unique_id', 'unknown')
                status = result.get('status', 'unknown')
                execution_time = result.get('execution_time', 0)
                response += f"- {node_id.split('.')[-1]}: {status} ({execution_time:.2f}s)\n"
            
            if len(results_list) > 20:
                response += f"\n... and {len(results_list) - 20} more\n"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "get_manifest":
            manifest_path = Path(DBT_PROJECT_DIR) / "target" / "manifest.json"
            
            if not manifest_path.exists():
                return [types.TextContent(
                    type="text",
                    text="No manifest found. Run `dbt docs generate` or `dbt compile` first."
                )]
            
            content = manifest_path.read_text()
            manifest = json.loads(content)
            
            model_name = arguments.get("model_name")
            
            if model_name:
                # Find specific model
                model_key = f"model.synthea_fhir.{model_name}"
                model_data = manifest.get('nodes', {}).get(model_key)
                
                if model_data:
                    response = f"**Model: {model_name}**\n\n"
                    response += f"Schema: {model_data.get('schema')}\n"
                    response += f"Database: {model_data.get('database')}\n"
                    response += f"Materialization: {model_data.get('config', {}).get('materialized')}\n"
                    response += f"Tags: {', '.join(model_data.get('tags', []))}\n\n"
                    
                    response += f"**Dependencies:**\n"
                    for dep in model_data.get('depends_on', {}).get('nodes', []):
                        response += f"- {dep.split('.')[-1]}\n"
                    
                    response += f"\n**Description:**\n{model_data.get('description', 'No description')}\n"
                else:
                    response = f"Model '{model_name}' not found in manifest"
            else:
                # Summary of all models
                models = {k: v for k, v in manifest.get('nodes', {}).items() if k.startswith('model.')}
                response = f"**DBT Project Manifest**\n\n"
                response += f"Total models: {len(models)}\n"
                response += f"dbt version: {manifest.get('metadata', {}).get('dbt_version')}\n"
                response += f"Generated at: {manifest.get('metadata', {}).get('generated_at')}\n\n"
                
                # Group by schema
                by_schema = {}
                for key, model in models.items():
                    schema = model.get('schema', 'unknown')
                    if schema not in by_schema:
                        by_schema[schema] = []
                    by_schema[schema].append(key.split('.')[-1])
                
                for schema, model_list in by_schema.items():
                    response += f"**{schema}:** {len(model_list)} models\n"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_snapshot":
            args = []
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])

            result = await run_dbt_command("snapshot", *args)
            
            response = f"**DBT Snapshot Results**\n\n"
            response += f"Success: {result['success']}\n\n"
            response += f"```\n{result['stdout'][-1000:]}\n```"
            
            return [types.TextContent(type="text", text=response)]

        elif name == "dbt_source_freshness":
            args = []
            if arguments.get("select"):
                args.extend(["--select", arguments["select"]])

            result = await run_dbt_command("source", "freshness", *args)
            
            response = f"**DBT Source Freshness Check**\n\n"
            response += f"Success: {result['success']}\n\n"
            response += f"```\n{result['stdout'][-1000:]}\n```"
            
            return [types.TextContent(type="text", text=response)]

        else:
            return [types.TextContent(
                type="text",
                text=f"Unknown tool: {name}"
            )]

    except Exception as e:
        logger.error(f"Error executing tool {name}: {str(e)}")
        return [types.TextContent(
            type="text",
            text=f"Error executing {name}: {str(e)}"
        )]


def get_file_content(file_path: Path) -> Optional[str]:
    """Read file content if exists."""
    try:
        if file_path.exists():
            return file_path.read_text()
    except Exception as e:
        logger.error(f"Error reading file {file_path}: {e}")
    return None


async def main():
    """Run the MCP server."""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="dbt-synthea-fhir",
                server_version="1.0.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    asyncio.run(main())
