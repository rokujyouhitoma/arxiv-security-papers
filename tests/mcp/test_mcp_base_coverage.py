#!/usr/bin/env python3
"""
Comprehensive Unit Tests for MCP Base Transport and Server Protocol Handlers.
"""

import io
import json
import os
from unittest.mock import patch

from mcp.base import (
    _dispatch_prompts_get,
    _dispatch_resources_read,
    _dispatch_tools_call,
    _extract_metrics,
    get_workspace_dir,
    log_mcp_performance,
    make_error_response,
    make_tool_response,
    run_mcp_server,
)
from mcp.tech_radar_server import TOOLS_MANIFEST as RADAR_TOOLS
from mcp.tech_radar_server import (
    handle_get_technology_radar,
    handle_predict_emerging_threats,
)
from mcp.threat_defense_server import TOOLS_MANIFEST as THREAT_TOOLS
from mcp.threat_defense_server import handle_check_threat_coverage


def test_get_workspace_dir():
    ws = get_workspace_dir()
    assert os.path.exists(ws)
    assert os.path.isabs(ws)


def test_make_tool_and_error_response():
    resp = make_tool_response(
        data={"result": "ok", "items": [1, 2, 3]},
        meta={"version": "1.0"},
    )
    assert resp["status"] == "success"
    assert resp["result"] == "ok"
    assert resp["_meta"]["version"] == "1.0"

    err_resp = make_error_response(
        message="Invalid argument",
        code="INVALID_ARG",
        details={"field": "query"},
    )
    assert err_resp["status"] == "error"
    assert err_resp["error_code"] == "INVALID_ARG"
    assert err_resp["message"] == "Invalid argument"
    assert err_resp["details"]["field"] == "query"


def test_log_mcp_performance_and_metrics():
    # Test metric extraction
    assert _extract_metrics({"count": 42}) == {"count": 42}
    assert _extract_metrics({"results": [1, 2, 3]}) == {"count": 3}
    assert _extract_metrics({"papers": [1, 2]}) == {"count": 2}
    assert _extract_metrics({}) == {}

    # Test performance logger
    log_mcp_performance(
        server_name="test_server",
        method="tools/call",
        name="test_tool",
        execution_ms=12.5,
        status="success",
        cpu_ms=8.0,
        peak_memory_kb=128.0,
        memory_delta_kb=10.0,
        args_summary={"query": "test"},
        metrics={"count": 5},
    )

    # Test error logging
    log_mcp_performance(
        server_name="test_server",
        method="tools/call",
        name="fail_tool",
        execution_ms=5.0,
        status="error",
        error_message="Simulated error",
    )


def test_dispatch_tools_call_success_and_errors():
    handlers = {
        "success_tool": lambda args: {"status": "success", "data": args},
        "error_tool": lambda args: {"status": "error", "message": "Failed"},
        "raise_tool": lambda args: 1 / 0,
    }

    # Success tool
    res1 = _dispatch_tools_call(
        "test_srv", {"name": "success_tool", "arguments": {"x": 1}}, handlers
    )
    assert "content" in res1

    # Error status tool
    res2 = _dispatch_tools_call(
        "test_srv", {"name": "error_tool", "arguments": {}}, handlers
    )
    assert "content" in res2

    # Exception tool
    res3 = _dispatch_tools_call(
        "test_srv", {"name": "raise_tool", "arguments": {}}, handlers
    )
    assert "content" in res3

    # Unknown tool
    res4 = _dispatch_tools_call(
        "test_srv", {"name": "unknown_tool", "arguments": {}}, handlers
    )
    assert "content" in res4


def test_dispatch_prompts_and_resources():
    p_handlers = {
        "summary_prompt": lambda args: {
            "messages": [{"role": "user", "content": "hello"}]
        },
        "error_prompt": lambda args: 1 / 0,
    }
    r_handlers = {
        "arxiv://test": lambda uri: {"contents": [{"uri": uri, "text": "content"}]},
        "error://test": lambda uri: 1 / 0,
    }

    # Prompts get
    res_p1 = _dispatch_prompts_get("test_srv", {"name": "summary_prompt"}, p_handlers)
    assert "messages" in res_p1

    res_p2 = _dispatch_prompts_get("test_srv", {"name": "error_prompt"}, p_handlers)
    assert "error" in res_p2

    res_p3 = _dispatch_prompts_get("test_srv", {"name": "unknown_prompt"}, p_handlers)
    assert "error" in res_p3

    # Resources read
    res_r1 = _dispatch_resources_read("test_srv", {"uri": "arxiv://test"}, r_handlers)
    assert "contents" in res_r1

    res_r2 = _dispatch_resources_read("test_srv", {"uri": "error://test"}, r_handlers)
    assert "error" in res_r2

    res_r3 = _dispatch_resources_read("test_srv", {"uri": "unknown://test"}, r_handlers)
    assert "error" in res_r3


def test_run_mcp_server_loop():
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "test", "arguments": {}},
        },
        {"jsonrpc": "2.0", "id": 4, "method": "prompts/list"},
        {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "prompts/get",
            "params": {"name": "test"},
        },
        {"jsonrpc": "2.0", "id": 6, "method": "resources/list"},
        {
            "jsonrpc": "2.0",
            "id": 7,
            "method": "resources/read",
            "params": {"uri": "test://uri"},
        },
        {"jsonrpc": "2.0", "id": 8, "method": "unknown_method"},
        {"jsonrpc": "2.0", "id": 9},  # Missing method
    ]
    input_str = "\n".join(json.dumps(r) for r in requests) + "\n"

    stdin_mock = io.StringIO(input_str)
    stdout_mock = io.StringIO()

    with patch("sys.stdin", stdin_mock), patch("sys.stdout", stdout_mock):
        run_mcp_server(
            server_name="mock_server",
            tools_manifest=[{"name": "test"}],
            prompts_manifest=[{"name": "test"}],
            resources_manifest=[{"uri": "test://uri"}],
            tool_handlers={"test": lambda args: {"result": "ok"}},
            prompt_handlers={"test": lambda args: {"messages": []}},
            resource_handlers={"test://uri": lambda uri: {"contents": []}},
        )

    out_lines = stdout_mock.getvalue().strip().split("\n")
    assert len(out_lines) >= 8


def test_tech_radar_and_threat_defense_servers():
    # Test Tech Radar manifests & handlers
    assert len(RADAR_TOOLS) > 0
    res_radar = handle_get_technology_radar({"category": "cryptography"})
    assert res_radar["status"] == "success"

    res_threats = handle_predict_emerging_threats({"min_severity": "HIGH"})
    assert res_threats["status"] == "success"

    # Test Threat Defense manifests & handlers
    assert len(THREAT_TOOLS) > 0
    res_coverage = handle_check_threat_coverage(
        {"declared_defenses": ["pickle-free", "ast-guard"]}
    )
    assert res_coverage["status"] == "success"

    from mcp.threat_defense_server import (
        handle_generate_semgrep_rule,
        handle_synthesize_secure_patch,
    )

    # Patch synthesis
    p_pickle = handle_synthesize_secure_patch(
        {"cwe_id": "CWE-502", "code": "import pickle\npickle.loads(data)"}
    )
    assert "json.loads(" in p_pickle["suggested_patch"]

    p_eval = handle_synthesize_secure_patch({"cwe_id": "CWE-94", "code": "eval(code)"})
    assert "ast.literal_eval" in p_eval["suggested_patch"]

    p_sql = handle_synthesize_secure_patch(
        {"cwe_id": "CWE-89", "code": "f\"SELECT * FROM users WHERE name = '{user}'\""}
    )
    assert "SELECT" in p_sql["suggested_patch"]

    # Semgrep rule generation
    sg = handle_generate_semgrep_rule({"cwe_id": "CWE-502"})
    assert sg["status"] == "success"


def test_papers_server_handlers_coverage():
    from mcp.papers_server import (
        handle_get_cwe_mitigation_recipe,
        handle_get_latest_trends,
        handle_get_paper_summary,
        handle_get_related_papers_graph,
        handle_query_attack_technique,
        handle_query_knowledge_graph,
        handle_search_papers_hybrid,
        handle_search_security_papers,
        handle_verify_code_security,
    )

    # Search security papers
    res_search = handle_search_security_papers({"query": "zero trust", "top_k": 2})
    assert isinstance(res_search, dict)

    # Hybrid search
    res_hybrid = handle_search_papers_hybrid(
        {"query": "lattice cryptography", "top_k": 2}
    )
    assert isinstance(res_hybrid, dict)

    # CWE recipe
    res_cwe = handle_get_cwe_mitigation_recipe({"cwe_id": "CWE-502"})
    assert isinstance(res_cwe, dict)

    # Attack technique
    res_tech = handle_query_attack_technique({"technique_id": "T1587.001"})
    assert isinstance(res_tech, dict)

    # Latest trends
    res_trends = handle_get_latest_trends({"limit": 5})
    assert isinstance(res_trends, dict)

    # KG Query
    res_kg = handle_query_knowledge_graph({"entity": "マルウェア・脅威解析"})
    assert isinstance(res_kg, dict)

    # Related papers graph
    res_rel = handle_get_related_papers_graph({"paper_id": "nonexistent_2026"})
    assert isinstance(res_rel, dict)

    # Verify code security
    res_sec = handle_verify_code_security({"code_snippet": "eval(user_input)"})
    assert isinstance(res_sec, dict)

    # Paper summary
    res_sum = handle_get_paper_summary({"paper_id": "nonexistent_id"})
    assert isinstance(res_sum, dict)

    from mcp.papers_server import handle_get_prompt, handle_read_resource

    # Read resources
    r1 = handle_read_resource("arxiv://cwe-taxonomy")
    assert r1.get("mimeType") == "application/json"
    r2 = handle_read_resource("arxiv://trends/latest")
    assert isinstance(r2, dict)
    r3 = handle_read_resource("arxiv://paper/2401.00001")
    assert isinstance(r3, dict)
    r4 = handle_read_resource("unknown://uri")
    assert r4.get("status") == "error"

    # Get prompts
    p1 = handle_get_prompt(
        "audit_code_with_papers", {"code": "import os; os.system(cmd)"}
    )
    assert "messages" in p1
    p2 = handle_get_prompt("generate_exploit_poc_tests", {"arxiv_id": "2401.00001"})
    assert "messages" in p2
    p3 = handle_get_prompt("unknown_prompt", {})
    assert isinstance(p3, dict)
