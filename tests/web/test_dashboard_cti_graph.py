#!/usr/bin/env python3
"""
Unit tests for CTI Knowledge Graph API (/api/graph/cti-mesh) and dashboard.html visualization.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, Dict, List

from web.gateway.app import WSGIApplication


def test_api_graph_cti_mesh_endpoint() -> None:
    """Verifies /api/graph/cti-mesh returns valid JSON schema conforming to DSN-14 Section 11."""
    app = WSGIApplication()

    status_code = ""
    response_headers: List[tuple[str, str]] = []

    def start_response(status: str, headers: List[tuple[str, str]]) -> None:
        nonlocal status_code, response_headers
        status_code = status
        response_headers = headers

    environ: Dict[str, Any] = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/api/graph/cti-mesh",
        "QUERY_STRING": "limit=25",
        "wsgi.input": None,
    }

    body_bytes = b"".join(app(environ, start_response))
    assert status_code.startswith("200")

    payload = json.loads(body_bytes.decode("utf-8"))
    assert payload["status"] == "success"
    assert "mesh" in payload
    assert "nodes" in payload["mesh"]
    assert "edges" in payload["mesh"]
    assert "stats" in payload
    assert "research_gaps" in payload

    stats = payload["stats"]
    assert "total_papers" in stats
    assert "total_techniques" in stats
    assert "total_cwes" in stats
    assert "research_gap_count" in stats

    # Nodes count should respect limit
    assert len(payload["mesh"]["nodes"]) <= 25

    # Check node attributes
    if payload["mesh"]["nodes"]:
        n = payload["mesh"]["nodes"][0]
        assert "id" in n
        assert "label" in n
        assert "color" in n
        assert "radius" in n


def test_dashboard_cti_mode_elements() -> None:
    """Verifies that site/dashboard.html includes all required CTI controls and legends."""
    dash_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "dashboard.html")
    )
    with open(dash_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Verify CTI Mode buttons & filters
    assert 'id="btnModeMesh"' in content
    assert 'id="btnModeCti"' in content
    assert 'id="ctiFilters"' in content
    assert 'id="valGapCount"' in content
    assert 'id="btnToggleGaps"' in content

    # Verify CTI legend elements
    assert 'id="ctiLegend"' in content
    assert "EXPLOITS (Solid)" in content
    assert "MITIGATES (Dashed)" in content
    assert "DISCLOSES (Solid)" in content
    assert "SUBCLASS_OF (Dotted)" in content

    # Verify JavaScript API handler hook
    assert "/api/graph/cti-mesh" in content
    assert "calculateTwoHopNeighborhood" in content
    assert "escapeHtml" in content

    # Verify zero external dependencies
    external_scripts = re.findall(r'<script\s+[^>]*src=["\'](http|//)', content, re.I)
    assert len(external_scripts) == 0
