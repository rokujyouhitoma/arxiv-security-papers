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

    # Check edge attributes for confidence and inference metadata
    if payload["mesh"]["edges"]:
        e = payload["mesh"]["edges"][0]
        assert "confidence" in e
        assert "confidence_tier" in e
        assert "primary_rule_id" in e
        assert "inference_mechanism" in e
        assert "evidence_quote" in e


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

    # Verify Confidence & Rule filters
    assert 'id="btnConfAll"' in content
    assert 'id="btnConfMed"' in content
    assert 'id="btnConfHigh"' in content
    assert 'id="selectEdgeRule"' in content

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


def test_cti_filter_buttons_use_css_color_badges() -> None:
    """Verify Issue #182: CTI filter buttons use clean CSS .filter-dot badges without OS emojis."""
    html_path = os.path.join(os.path.dirname(__file__), "../../site/dashboard.html")
    with open(html_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Verify .filter-dot CSS definition
    assert ".filter-dot {" in content
    assert ".btn-tool.active .filter-dot" in content

    # 2. Verify all CTI filter buttons contain .filter-dot with designated color
    expected_buttons = {
        'id="filterPaper"': "#3B82F6",
        'id="filterAttack"': "#EF4444",
        'id="filterCwe"': "#F59E0B",
        'id="filterPrecondition"': "#EAB308",
        'id="filterRule"': "#10B981",
        'id="filterPoc"': "#06B6D4",
        'id="filterGap"': "#8B5CF6",
    }
    for btn_id, color in expected_buttons.items():
        assert btn_id in content
        # Ensure .filter-dot with the exact color is inside the button definition
        btn_pattern = rf'{btn_id}[^>]*>.*?<span class="filter-dot" style="background-color: {color};"></span>'
        assert re.search(
            btn_pattern, content, re.DOTALL
        ), f"Button {btn_id} missing filter-dot with {color}"

    # 3. Verify emojis are eradicated from #ctiFilters section
    cti_filters_match = re.search(
        r'<div id="ctiFilters".*?</div>\s*</div>', content, re.DOTALL
    )
    assert cti_filters_match is not None
    cti_filters_html = cti_filters_match.group(0)
    for emoji in ["🔵", "🔴", "🟠", "🟡", "🟢", "🔷", "🟣"]:
        assert (
            emoji not in cti_filters_html
        ), f"Unexpected emoji {emoji} found in ctiFilters"


def test_cti_entity_filter_multiselect_implementation() -> None:
    """Verify Issue #183: CTI Entity Type filter supports multiselect (Set-based state)."""
    html_path = os.path.join(os.path.dirname(__file__), "../../site/dashboard.html")
    with open(html_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Set-based state variable instead of single string
    assert "ctiEntityFilters" in content
    assert "new Set(['all'])" in content

    # 2. toggleCtiEntityFilter function must exist
    assert "window.toggleCtiEntityFilter" in content

    # 3. syncEntityFilterButtons must be defined
    assert "function syncEntityFilterButtons()" in content

    # 4. All filter buttons use toggleCtiEntityFilter onclick
    multiselect_btns = [
        "filterAll",
        "filterPaper",
        "filterAttack",
        "filterCwe",
        "filterPrecondition",
        "filterRule",
        "filterPoc",
        "filterGap",
    ]
    for btn_id in multiselect_btns:
        assert f'id="{btn_id}"' in content, f"Missing button #{btn_id}"
        # Each button must link to the new toggle function
        btn_pattern = rf'id="{btn_id}"[^>]*toggleCtiEntityFilter'
        assert re.search(
            btn_pattern, content
        ), f"Button #{btn_id} must use toggleCtiEntityFilter()"

    # 5. CTI_ENTITY_LABEL_MAP must be defined (Set-based matcher)
    assert "CTI_ENTITY_LABEL_MAP" in content
    assert "CTI_ENTITY_TYPES" in content

    # 6. Guard: at-least-one selected logic
    assert "ctiEntityFilters.size === 0" in content
    assert "new Set(['all'])" in content

    # 7. All-collapse logic (all individuals → 'all')
    assert "CTI_ENTITY_TYPES.every" in content

    # 8. Legacy setCtiFilter kept for backward compatibility
    assert "window.setCtiFilter" in content


def test_cti_filter_multiselect_applyCtiFilter_uses_set() -> None:
    """Verify that applyCtiFilter uses Set-based iteration (ctiEntityFilters) not old single string."""
    html_path = os.path.join(os.path.dirname(__file__), "../../site/dashboard.html")
    with open(html_path, "r", encoding="utf-8") as f:
        content = f.read()

    # New Set-based check
    assert "ctiEntityFilters.has('all')" in content
    assert "for (const type of ctiEntityFilters)" in content

    # Old single-string check must be absent in applyCtiFilter context
    assert "ctiFilter !== 'all'" not in content
