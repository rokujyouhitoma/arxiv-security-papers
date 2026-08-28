"""
Unit tests for Graph Engineering Dashboard (site/dashboard.html) and Web Gateway routing.
Verifies zero external dependencies, strict self-contained Pure JS/CSS/Canvas, and HTML structure.
"""

import io
import os
import re
from typing import Any, List

import pytest

from web.gateway.app import WSGIApplication


@pytest.fixture
def dashboard_html_content() -> str:
    path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "dashboard.html")
    )
    assert os.path.exists(path), f"dashboard.html not found at {path}"
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_dashboard_zero_external_dependencies(dashboard_html_content: str) -> None:
    """Verifies that dashboard.html does not contain any external script or stylesheet links."""
    # Find all script src tags
    script_srcs = re.findall(
        r'<script\s+[^>]*src=["\']([^"\']+)["\']', dashboard_html_content, re.IGNORECASE
    )
    for src in script_srcs:
        assert not src.startswith(
            ("http://", "https://", "//")
        ), f"External script found: {src}"

    # Find all link rel="stylesheet" tags
    css_hrefs = re.findall(
        r'<link\s+[^>]*href=["\']([^"\']+)["\']', dashboard_html_content, re.IGNORECASE
    )
    for href in css_hrefs:
        assert not href.startswith(
            ("http://", "https://", "//")
        ), f"External stylesheet found: {href}"


def test_dashboard_mandatory_elements_and_canvas(dashboard_html_content: str) -> None:
    """Verifies all mandatory UI telemetry, force-directed canvas, OBF status, and micro-charts exist."""
    assert '<canvas id="graphCanvas"' in dashboard_html_content
    assert 'id="valResolvedNodes"' in dashboard_html_content
    assert 'id="valEdgesTick"' in dashboard_html_content
    assert 'id="valObfStatus"' in dashboard_html_content
    assert 'id="valObfSpans"' in dashboard_html_content
    assert "OBF Telemetry" in dashboard_html_content
    assert 'id="pipelineBar"' in dashboard_html_content
    assert 'id="hopCanvas"' in dashboard_html_content
    assert 'id="walkVsFlatCanvas"' in dashboard_html_content
    assert 'id="traversalMatrix"' in dashboard_html_content
    assert 'id="nodeCallout"' in dashboard_html_content
    assert "Graph Engineering" in dashboard_html_content
    assert 'id="tabBtnProduct"' in dashboard_html_content
    assert 'id="tabBtnSystem"' in dashboard_html_content
    assert 'id="tabBtnSupervisor"' in dashboard_html_content
    assert 'id="viewProduct"' in dashboard_html_content
    assert 'id="viewSystem"' in dashboard_html_content
    assert 'id="viewSupervisor"' in dashboard_html_content
    assert 'id="supervisorWorkersTableBody"' in dashboard_html_content
    assert 'id="valTokenRoi"' in dashboard_html_content
    assert 'id="threatVectorsList"' in dashboard_html_content
    assert 'id="valSmPipelineSlo"' in dashboard_html_content
    assert 'id="valSmApiResilience"' in dashboard_html_content
    assert 'id="valSaTailLatency"' in dashboard_html_content
    assert 'id="valSaMttr"' in dashboard_html_content
    assert "switchDashboardTab" in dashboard_html_content
    assert "initTabFromUrl" in dashboard_html_content
    assert "URLSearchParams" in dashboard_html_content
    assert "Context Mesh" in dashboard_html_content


def test_gateway_dashboard_routing() -> None:
    """Verifies that the web gateway correctly serves dashboard.html for /dashboard and /dashboard.html."""
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    # 1. Test /dashboard.html
    captured_status = []
    captured_headers = []

    def start_response(status: str, headers: List[Any], exc_info: Any = None) -> None:
        captured_status.append(status)
        captured_headers.append(headers)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/dashboard.html",
        "QUERY_STRING": "",
        "wsgi.input": io.BytesIO(b""),
    }
    body = app(environ, start_response)
    raw = b"".join(body).decode("utf-8")
    assert captured_status[0] == "200 OK"
    assert "Graph Engineering" in raw

    # 2. Test /dashboard alias
    captured_status.clear()
    environ["PATH_INFO"] = "/dashboard"
    body_alias = app(environ, start_response)
    raw_alias = b"".join(body_alias).decode("utf-8")
    assert captured_status[0] == "200 OK"
    assert "Graph Engineering" in raw_alias


def test_gateway_graph_mesh_api() -> None:
    """Verifies that the /api/graph/mesh endpoint returns valid 4-cluster mesh graph data."""
    import json

    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    captured_status = []
    captured_headers = []

    def start_response(status: str, headers: List[Any], exc_info: Any = None) -> None:
        captured_status.append(status)
        captured_headers.append(headers)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/graph/mesh",
        "QUERY_STRING": "",
        "wsgi.input": io.BytesIO(b""),
    }
    body = app(environ, start_response)
    raw = b"".join(body).decode("utf-8")
    assert captured_status[0] == "200 OK"
    data = json.loads(raw)
    assert data["status"] == "success"
    assert "mesh" in data
    assert "nodes" in data["mesh"]
    assert "edges" in data["mesh"]
    assert len(data["mesh"]["nodes"]) > 0
    assert len(data["mesh"]["edges"]) > 0
    assert "telemetry" in data
    assert data["telemetry"]["token_savings_pct"] == 74.2


def test_gateway_graph_mesh_with_vector_engine() -> None:
    """Verifies graph mesh generation when vector_engine with real documents is attached."""
    import json
    from unittest.mock import MagicMock

    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    mock_engine = MagicMock()
    mock_engine.documents = [
        {
            "clean_id": "2608.23763",
            "title": "TrustShiftProbe: Staged Defection in MCP",
            "description": "MCP server defecting behavior audit",
            "tags": ["mcp-protocol", "agent-security"],
        },
        {
            "clean_id": "2608.23550",
            "title": "CLAUDE.md Rules vs Built-in Controls",
            "description": "Permission gap in prompt instructions",
            "tags": ["prompt-injection", "sandbox"],
        },
    ]
    app = WSGIApplication(workspace_dir=workspace_dir, vector_engine=mock_engine)

    captured_status = []
    captured_headers = []

    def start_response(status: str, headers: List[Any], exc_info: Any = None) -> None:
        captured_status.append(status)
        captured_headers.append(headers)

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/graph/mesh",
        "QUERY_STRING": "",
        "wsgi.input": io.BytesIO(b""),
    }
    body = app(environ, start_response)
    raw = b"".join(body).decode("utf-8")
    assert captured_status[0] == "200 OK"
    data = json.loads(raw)
    assert data["status"] == "success"
    assert len(data["mesh"]["nodes"]) == 8
    assert len(data["mesh"]["edges"]) == 8
    assert "database_metrics" in data
    db_m = data["database_metrics"]
    assert db_m["table_count"] >= 5
    assert db_m["total_rows"] > 0
    assert "performance_kpis" in db_m
    assert db_m["performance_kpis"]["read_iops"] > 0


def test_dashboard_database_storage_metrics_ui(dashboard_html_content: str) -> None:
    """Verifies that the System tab contains the Database Performance, IOPS, and Tables Breakdown elements."""
    assert 'id="valDbIops"' in dashboard_html_content
    assert 'id="valDbLatency"' in dashboard_html_content
    assert 'id="valDbCacheHit"' in dashboard_html_content
    assert 'id="badgeDbTableCount"' in dashboard_html_content
    assert 'id="badgeDbTotalRows"' in dashboard_html_content
    assert 'id="badgeDbTotalSize"' in dashboard_html_content
    assert 'id="databaseTablesTableBody"' in dashboard_html_content
    assert "Database Tables &amp; Physical Storage Ledger" in dashboard_html_content
    assert 'id="valDbCurrentDb"' in dashboard_html_content
    assert 'id="sqlResultDatabases"' in dashboard_html_content
    assert 'id="sqlResultTablesSummary"' in dashboard_html_content
    assert "SHOW DATABASES" in dashboard_html_content
    assert "SHOW TABLES FROM arxiv_security_db" in dashboard_html_content


def test_dashboard_supervisor_tab_ui(dashboard_html_content: str) -> None:
    """Verifies that the Supervisor tab contains Arbiter Process, Worker Pools, IPC Channel, and Workers Table."""
    assert 'id="viewSupervisor"' in dashboard_html_content
    assert 'id="badgeArbiterStatus"' in dashboard_html_content
    assert 'id="valArbiterPid"' in dashboard_html_content
    assert 'id="valArbiterUptime"' in dashboard_html_content
    assert 'id="valArbiterMemory"' in dashboard_html_content
    assert 'id="badgePoolCount"' in dashboard_html_content
    assert 'id="valArbiterPools"' in dashboard_html_content
    assert 'id="badgeIpcStatus"' in dashboard_html_content
    assert 'id="badgeTotalWorkers"' in dashboard_html_content
    assert 'id="supervisorWorkersTableBody"' in dashboard_html_content
    assert 'id="badgeSaLatency"' in dashboard_html_content
    assert 'id="valSaTailLatency"' in dashboard_html_content
    assert 'id="valSaMttr"' in dashboard_html_content
    assert 'id="valSaDensity"' in dashboard_html_content
    # Check that viewSupervisor is closed and clean
    assert '<div id="viewSupervisor" class="tab-view">' in dashboard_html_content
