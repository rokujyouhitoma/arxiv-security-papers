#!/usr/bin/env python3
"""
Unit tests for Observability MCP Server (JSON-RPC 2.0).
"""

import json
import os
import sys

if "src" not in sys.path:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from observability_mcp_server import dispatch_rpc_request


def test_mcp_initialize():
    req = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
    resp = dispatch_rpc_request(req)
    assert resp is not None
    assert resp["id"] == 1
    assert "capabilities" in resp["result"]
    assert resp["result"]["serverInfo"]["name"] == "arxiv-security-observability-mcp-server"


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
                    {"name": "for_loop", "code": "res = []\nfor x in range(100):\n    res.append(x * 2)"},
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
            "arguments": {"function_name": "calc_score", "profile_summary": "10.5s in loop"},
        },
    }
    resp_prompt = dispatch_rpc_request(req_prompt)
    assert "calc_score" in resp_prompt["result"]["messages"][0]["content"]["text"]
