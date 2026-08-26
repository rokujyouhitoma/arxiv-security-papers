"""
Unit tests for Graph Engineering Dashboard (site/dashboard.html) and Web Gateway routing.
Verifies zero external dependencies, strict self-contained Pure JS/CSS/Canvas, and HTML structure.
"""

import io
import os
import re
from typing import Any, Dict, List

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
    script_srcs = re.findall(r'<script\s+[^>]*src=["\']([^"\']+)["\']', dashboard_html_content, re.IGNORECASE)
    for src in script_srcs:
        assert not src.startswith(("http://", "https://", "//")), f"External script found: {src}"

    # Find all link rel="stylesheet" tags
    css_hrefs = re.findall(r'<link\s+[^>]*href=["\']([^"\']+)["\']', dashboard_html_content, re.IGNORECASE)
    for href in css_hrefs:
        assert not href.startswith(("http://", "https://", "//")), f"External stylesheet found: {href}"


def test_dashboard_mandatory_elements_and_canvas(dashboard_html_content: str) -> None:
    """Verifies all mandatory UI telemetry, force-directed canvas, and micro-charts exist."""
    assert '<canvas id="graphCanvas"' in dashboard_html_content
    assert 'id="valResolvedNodes"' in dashboard_html_content
    assert 'id="valEdgesTick"' in dashboard_html_content
    assert 'id="pipelineBar"' in dashboard_html_content
    assert 'id="hopCanvas"' in dashboard_html_content
    assert 'id="walkCanvas"' in dashboard_html_content
    assert 'id="traversalMatrix"' in dashboard_html_content
    assert 'id="nodeCallout"' in dashboard_html_content
    assert 'Graph Engineering' in dashboard_html_content
    assert 'Context Mesh' in dashboard_html_content


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
