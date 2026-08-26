"""
Unit tests for MCP usage analytics and metrics aggregation engine (src/mcp/analytics.py).
"""

import json
import os
import tempfile
from typing import Any, Dict, List

import pytest

from mcp.analytics import (
    compute_mcp_metrics,
    export_mcp_report_file,
    load_mcp_logs,
    render_mcp_markdown_report,
)


@pytest.fixture
def sample_jsonl_log() -> str:
    records: List[Dict[str, Any]] = [
        {
            "timestamp": "2026-08-26T12:00:00Z",
            "server": "arxiv-security-papers",
            "method": "tools/call",
            "name": "search_security_papers",
            "execution_ms": 15.5,
            "peak_memory_kb": 256.0,
            "status": "success",
            "metrics": {"count": 10},
        },
        {
            "timestamp": "2026-08-26T12:05:00Z",
            "server": "arxiv-security-papers",
            "method": "tools/call",
            "name": "compact_search",
            "execution_ms": 5.2,
            "peak_memory_kb": 128.0,
            "status": "success",
            "metrics": {"count": 5},
        },
        {
            "timestamp": "2026-08-26T12:10:00Z",
            "server": "arxiv-security-papers",
            "method": "tools/call",
            "name": "get_paper_details",
            "execution_ms": 1.1,
            "peak_memory_kb": 64.0,
            "status": "error",
            "error": "Paper not found",
        },
        {
            "timestamp": "2026-08-26T13:00:00Z",
            "server": "threat-defense-mcp",
            "method": "tools/call",
            "name": "generate_semgrep_rule",
            "execution_ms": 42.0,
            "peak_memory_kb": 512.0,
            "status": "success",
        },
    ]

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".jsonl", delete=False, encoding="utf-8"
    ) as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
        f.write("\n")  # Empty line test
        f.write("corrupted json line\n")  # Bad line test
        temp_path = f.name

    return temp_path


def test_load_mcp_logs(sample_jsonl_log: str) -> None:
    records = load_mcp_logs(sample_jsonl_log)
    assert len(records) == 4

    # Server filter test
    threat_records = load_mcp_logs(sample_jsonl_log, server_filter="threat-defense-mcp")
    assert len(threat_records) == 1
    assert threat_records[0]["name"] == "generate_semgrep_rule"

    os.remove(sample_jsonl_log)


def test_compute_mcp_metrics(sample_jsonl_log: str) -> None:
    records = load_mcp_logs(sample_jsonl_log)
    metrics = compute_mcp_metrics(records)

    assert metrics["total_requests"] == 4
    assert metrics["success_count"] == 3
    assert metrics["error_count"] == 1
    assert metrics["success_rate_pct"] == 75.0
    assert metrics["avg_execution_ms"] == round((15.5 + 5.2 + 1.1 + 42.0) / 4, 2)

    # Tool stats
    tools = metrics["tools"]
    assert "search_security_papers" in tools
    assert tools["search_security_papers"]["calls"] == 1
    assert tools["search_security_papers"]["success_rate"] == 100.0

    assert "get_paper_details" in tools
    assert tools["get_paper_details"]["error"] == 1
    assert tools["get_paper_details"]["success_rate"] == 0.0

    # Error tracking
    errors = metrics["recent_errors"]
    assert len(errors) == 1
    assert errors[0]["name"] == "get_paper_details"
    assert "not found" in errors[0]["error"]

    os.remove(sample_jsonl_log)


def test_render_and_export_markdown_report() -> None:
    dummy_metrics: Dict[str, Any] = {
        "total_requests": 10,
        "success_count": 9,
        "error_count": 1,
        "success_rate_pct": 90.0,
        "avg_execution_ms": 12.34,
        "servers": {"papers_server": 8, "observability_server": 2},
        "methods": {"tools/call": 10},
        "tools": {
            "search_security_papers": {
                "calls": 8,
                "success": 8,
                "error": 0,
                "success_rate": 100.0,
                "avg_ms": 10.5,
                "min_ms": 2.0,
                "max_ms": 25.0,
                "avg_mem_kb": 200.0,
                "max_mem_kb": 400.0,
            }
        },
        "recent_errors": [
            {
                "timestamp": "2026-08-26T12:00:00Z",
                "server": "papers_server",
                "name": "bad_tool",
                "error": "Unknown tool",
            }
        ],
    }

    report = render_mcp_markdown_report(dummy_metrics)
    assert "# 📊 Model Context Protocol (MCP) 利用状況・集計レポート" in report
    assert "papers_server" in report
    assert "search_security_papers" in report
    assert "90.0%" in report

    out_path = export_mcp_report_file(dummy_metrics)
    assert os.path.exists(out_path)
    with open(out_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Model Context Protocol" in content
