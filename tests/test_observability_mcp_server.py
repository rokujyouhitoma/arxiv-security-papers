#!/usr/bin/env python3
"""
Unit tests for Observability MCP Server (JSON-RPC 2.0).
"""

import json
import os
import sys

if "src" not in sys.path:
    sys.path.insert(
        0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
    )

from mcp.observability_server import dispatch_rpc_request


def test_mcp_initialize():
    req = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
    resp = dispatch_rpc_request(req)
    assert resp is not None
    assert resp["id"] == 1
    assert "capabilities" in resp["result"]
    assert (
        resp["result"]["serverInfo"]["name"]
        == "arxiv-security-observability-mcp-server"
    )


def test_mcp_tools_list():
    req = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
    resp = dispatch_rpc_request(req)
    assert resp is not None
    tools = resp["result"]["tools"]
    tool_names = {t["name"] for t in tools}
    assert "profile_code_performance" in tool_names
    assert "track_memory_allocations" in tool_names
    assert "benchmark_alternatives" in tool_names
    assert "inspect_bytecode" in tool_names
    assert "get_system_metrics" in tool_names


def test_mcp_tool_profile_code():
    code_to_profile = """
def calc():
    return sum(x*x for x in range(1000))
res = calc()
"""
    req = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "profile_code_performance",
            "arguments": {"code": code_to_profile, "top_n": 5},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert "wall_time_ms" in data
    assert "top_bottlenecks" in data
    assert "calc" in data["top_bottlenecks"] or "sum" in data["top_bottlenecks"]


def test_mcp_tool_track_memory():
    code_to_trace = """
data = [i for i in range(10000)]
"""
    req = {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "track_memory_allocations",
            "arguments": {"code": code_to_trace, "top_lines": 3},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert "peak_memory_kb" in data
    assert data["peak_memory_kb"] > 0
    assert len(data["top_allocations"]) > 0


def test_mcp_tool_benchmark_alternatives():
    req = {
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
            "name": "benchmark_alternatives",
            "arguments": {
                "candidates": [
                    {"name": "list_comp", "code": "res = [x * 2 for x in range(100)]"},
                    {
                        "name": "for_loop",
                        "code": "res = []\nfor x in range(100):\n    res.append(x * 2)",
                    },
                ],
                "number": 50,
                "repeat": 2,
            },
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert data["winner"] in ["list_comp", "for_loop"]
    assert len(data["comparisons"]) == 2
    assert "min_time_ms" in data["comparisons"][0]


def test_mcp_tool_inspect_bytecode():
    req = {
        "jsonrpc": "2.0",
        "id": 6,
        "method": "tools/call",
        "params": {
            "name": "inspect_bytecode",
            "arguments": {"code": "x = 10 + 20"},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert data["total_instructions"] > 0
    assert "instructions" in data


def test_mcp_tool_security_guard():
    req = {
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": {
            "name": "profile_code_performance",
            "arguments": {"code": "import subprocess\nsubprocess.run(['ls'])"},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert "error" in data
    assert "Security Exception" in data["error"]


def test_mcp_resources_and_prompts():
    # Resources list
    req_res = {"jsonrpc": "2.0", "id": 8, "method": "resources/list", "params": {}}
    resp_res = dispatch_rpc_request(req_res)
    assert len(resp_res["result"]["resources"]) >= 2

    # Prompts get
    req_prompt = {
        "jsonrpc": "2.0",
        "id": 9,
        "method": "prompts/get",
        "params": {
            "name": "optimize_bottleneck_prompt",
            "arguments": {
                "function_name": "calc_score",
                "profile_summary": "10.5s in loop",
            },
        },
    }
    resp_prompt = dispatch_rpc_request(req_prompt)
    assert "calc_score" in resp_prompt["result"]["messages"][0]["content"]["text"]


def test_mcp_system_metrics_memory_and_activity():
    req = {
        "jsonrpc": "2.0",
        "id": 10,
        "method": "tools/call",
        "params": {
            "name": "get_system_metrics",
            "arguments": {},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    content_text = resp["result"]["content"][0]["text"]
    data = json.loads(content_text)
    assert data["status"] == "healthy"
    assert "memory" in data
    assert "current_ram_kb" in data["memory"]
    assert "recent_activity" in data


def test_mcp_get_performance_logs_and_dump():
    # 1. get_performance_logs
    req_logs = {
        "jsonrpc": "2.0",
        "id": 11,
        "method": "tools/call",
        "params": {
            "name": "get_performance_logs",
            "arguments": {"log_type": "all", "limit": 10},
        },
    }
    resp_logs = dispatch_rpc_request(req_logs)
    assert resp_logs is not None
    data_logs = json.loads(resp_logs["result"]["content"][0]["text"])
    assert data_logs["status"] == "success"
    assert "summary" in data_logs
    assert "avg_latency_ms" in data_logs["summary"]

    # 2. dump_performance_metrics markdown
    req_dump_md = {
        "jsonrpc": "2.0",
        "id": 12,
        "method": "tools/call",
        "params": {
            "name": "dump_performance_metrics",
            "arguments": {"format": "markdown"},
        },
    }
    resp_dump_md = dispatch_rpc_request(req_dump_md)
    assert resp_dump_md is not None
    data_dump_md = json.loads(resp_dump_md["result"]["content"][0]["text"])
    assert data_dump_md["status"] == "success"
    assert "# 📊 統合可観測性" in data_dump_md["markdown_report"]

    # 3. dump_performance_metrics json
    req_dump_json = {
        "jsonrpc": "2.0",
        "id": 13,
        "method": "tools/call",
        "params": {
            "name": "dump_performance_metrics",
            "arguments": {"format": "json"},
        },
    }
    resp_dump_json = dispatch_rpc_request(req_dump_json)
    assert resp_dump_json is not None
    data_dump_json = json.loads(resp_dump_json["result"]["content"][0]["text"])
    assert data_dump_json["status"] == "success"
    assert "mcp" in data_dump_json["metrics"]
    assert "search" in data_dump_json["metrics"]


def test_mcp_base_and_search_logging_integration():
    from mcp.base import log_mcp_performance

    # Test MCP performance logging with memory and cpu metrics
    log_mcp_performance(
        server_name="test-server",
        method="tools/call",
        name="test_tool",
        execution_ms=12.345,
        status="success",
        cpu_ms=8.12,
        peak_memory_kb=256.0,
        memory_delta_kb=64.0,
        args_summary={"query": "test"},
        metrics={"count": 5},
    )

    # Verify get_performance_logs sees the entry
    req = {
        "jsonrpc": "2.0",
        "id": 14,
        "method": "tools/call",
        "params": {
            "name": "get_performance_logs",
            "arguments": {"log_type": "mcp", "limit": 5},
        },
    }
    resp = dispatch_rpc_request(req)
    assert resp is not None
    data = json.loads(resp["result"]["content"][0]["text"])
    assert data["status"] == "success"
    assert len(data["records"]) > 0
    recent = data["records"][0]
    assert "cpu_ms" in recent
    assert "peak_memory_kb" in recent
