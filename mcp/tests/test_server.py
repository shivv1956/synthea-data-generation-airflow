"""
Test suite for DBT MCP Server

Run with: pytest tests/test_server.py -v
"""

import asyncio
import json
import pytest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

# Import server components
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))
from server import run_dbt_command, server


@pytest.mark.asyncio
async def test_run_dbt_command_success():
    """Test successful dbt command execution"""
    with patch('asyncio.create_subprocess_exec') as mock_subprocess:
        # Mock successful process
        mock_process = AsyncMock()
        mock_process.communicate.return_value = (
            b"Completed successfully",
            b""
        )
        mock_process.returncode = 0
        mock_subprocess.return_value = mock_process
        
        result = await run_dbt_command("debug")
        
        assert result['success'] is True
        assert result['return_code'] == 0
        assert "Completed successfully" in result['stdout']


@pytest.mark.asyncio
async def test_run_dbt_command_failure():
    """Test failed dbt command execution"""
    with patch('asyncio.create_subprocess_exec') as mock_subprocess:
        # Mock failed process
        mock_process = AsyncMock()
        mock_process.communicate.return_value = (
            b"",
            b"Connection error"
        )
        mock_process.returncode = 1
        mock_subprocess.return_value = mock_process
        
        result = await run_dbt_command("run")
        
        assert result['success'] is False
        assert result['return_code'] == 1
        assert "Connection error" in result['stderr']


@pytest.mark.asyncio
async def test_run_dbt_command_timeout():
    """Test dbt command timeout"""
    with patch('asyncio.create_subprocess_exec') as mock_subprocess:
        mock_process = AsyncMock()
        mock_process.communicate.side_effect = asyncio.TimeoutError()
        mock_subprocess.return_value = mock_process
        
        result = await run_dbt_command("run", timeout=1)
        
        assert result['success'] is False
        assert "timed out" in result['stderr']


@pytest.mark.asyncio
async def test_list_tools():
    """Test that all expected tools are listed"""
    tools = await server.list_tools()
    
    tool_names = [tool.name for tool in tools]
    
    expected_tools = [
        "dbt_run",
        "dbt_test",
        "dbt_compile",
        "dbt_docs_generate",
        "dbt_list",
        "dbt_debug",
        "get_model_sql",
        "get_run_results",
        "get_manifest",
        "dbt_snapshot",
        "dbt_source_freshness"
    ]
    
    for expected in expected_tools:
        assert expected in tool_names, f"Missing tool: {expected}"


@pytest.mark.asyncio
async def test_dbt_run_tool():
    """Test dbt_run tool with various arguments"""
    with patch('server.run_dbt_command') as mock_run:
        mock_run.return_value = {
            'success': True,
            'return_code': 0,
            'stdout': 'Completed successfully',
            'stderr': ''
        }
        
        # Test with models filter
        result = await server.call_tool(
            "dbt_run",
            {"models": "stg_patients"}
        )
        
        assert len(result) > 0
        assert "Success: True" in result[0].text or "success" in result[0].text.lower()


@pytest.mark.asyncio
async def test_dbt_test_tool():
    """Test dbt_test tool"""
    with patch('server.run_dbt_command') as mock_run:
        mock_run.return_value = {
            'success': True,
            'return_code': 0,
            'stdout': 'All tests passed',
            'stderr': ''
        }
        
        result = await server.call_tool(
            "dbt_test",
            {"models": "stg_patients"}
        )
        
        assert len(result) > 0


def test_get_file_content_exists(tmp_path):
    """Test reading existing file"""
    from server import get_file_content
    
    test_file = tmp_path / "test.json"
    test_data = {"key": "value"}
    test_file.write_text(json.dumps(test_data))
    
    content = get_file_content(test_file)
    assert content is not None
    assert json.loads(content) == test_data


def test_get_file_content_not_exists():
    """Test reading non-existent file"""
    from server import get_file_content
    
    content = get_file_content(Path("/nonexistent/file.json"))
    assert content is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
