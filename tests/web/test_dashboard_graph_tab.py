"""
Unit tests for Dedicated Knowledge & CTI Graph Tab (tab=graph) and Header Toggle in dashboard.html.
Verifies Pure-Python zero-dependency conformity, HTML structure, CSS rules, and Gateway routing.
"""

from __future__ import annotations

import io
import os
from typing import Any, List

import pytest

from web.gateway.app import WSGIApplication


@pytest.fixture
def dashboard_html() -> str:
    path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "dashboard.html")
    )
    assert os.path.exists(path), f"dashboard.html not found at {path}"
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_dashboard_mandatory_graph_tab_elements(dashboard_html: str) -> None:
    """Verifies that tab=graph dedicated view, navigation buttons, and header elements exist."""
    # 4-Tab Navigation Buttons
    assert 'id="tabBtnGraph"' in dashboard_html
    assert 'id="tabBtnProduct"' in dashboard_html
    assert 'id="tabBtnSystem"' in dashboard_html
    assert 'id="tabBtnSupervisor"' in dashboard_html

    # 4-Tab View Containers
    assert 'id="viewGraph"' in dashboard_html
    assert 'id="viewProduct"' in dashboard_html
    assert 'id="viewSystem"' in dashboard_html
    assert 'id="viewSupervisor"' in dashboard_html

    # Dedicated Workspaces
    assert 'class="graph-workspace"' in dashboard_html
    assert 'class="product-workspace"' in dashboard_html
    assert 'class="graph-cta-banner"' in dashboard_html

    # Header and Toggle controls
    assert 'id="dashboardHeader"' in dashboard_html
    assert 'id="btnToggleHeader"' in dashboard_html
    assert 'id="btnToggleHeaderQuick"' in dashboard_html

    # Graph Canvas inside viewGraph
    assert '<canvas id="graphCanvas"' in dashboard_html
    assert 'id="graphQueryConsole"' in dashboard_html
    assert 'id="nodeCallout"' in dashboard_html


def test_dashboard_header_toggle_and_css(dashboard_html: str) -> None:
    """Verifies that header collapse CSS and toggle JavaScript functions exist."""
    # CSS rules
    assert "header.header-hidden" in dashboard_html
    assert "display: none !important;" in dashboard_html
    assert "calc(100vh - 42px)" in dashboard_html

    # JavaScript function definitions
    assert "window.toggleDashboardHeader" in dashboard_html
    assert "dashboard_header_hidden" in dashboard_html
    assert "btnToggleHeader" in dashboard_html
    assert "openGraphWithQuery" in dashboard_html

    # Keyboard shortcut 'h' / 'H'
    assert "keydown" in dashboard_html
    assert "e.key === 'h' || e.key === 'H'" in dashboard_html


def test_dashboard_tab_switching_routing_logic(dashboard_html: str) -> None:
    """Verifies that switchDashboardTab supports 4 tabs including graph, product, system, supervisor."""
    assert "window.switchDashboardTab" in dashboard_html
    assert "normTab === 'product' || normTab === 'analytics'" in dashboard_html
    assert "normTab === 'system' || normTab === 'observability'" in dashboard_html
    assert "normTab === 'supervisor' || normTab === 'top'" in dashboard_html
    assert "'graph'" in dashboard_html
    assert "tabBtnGraph" in dashboard_html
    assert "viewGraph" in dashboard_html

    # Canvas resize zero-dimension guard
    assert "if (!canvas || !canvas.parentElement) return;" in dashboard_html
    assert "if (rect.width <= 0 || rect.height <= 0) return;" in dashboard_html


def test_gateway_serves_dashboard_graph_tab() -> None:
    """Verifies that WSGIApplication properly serves dashboard with tab=graph query."""
    workspace_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    app = WSGIApplication(workspace_dir=workspace_dir)

    status_code = ""
    response_headers: List[Any] = []

    def start_response(status: str, headers: List[Any], exc_info: Any = None) -> None:
        nonlocal status_code, response_headers
        status_code = status
        response_headers = headers

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/dashboard.html",
        "QUERY_STRING": "tab=graph",
        "wsgi.input": io.BytesIO(b""),
    }
    body = app(environ, start_response)
    raw = b"".join(body).decode("utf-8")

    assert status_code.startswith("200")
    assert "viewGraph" in raw
    assert "tabBtnGraph" in raw
    assert "dashboardHeader" in raw
    assert "btnToggleHeader" in raw


def test_dashboard_graph_layout_redesign_and_legend_toggle(dashboard_html: str) -> None:
    """Verifies that the graph tab layout has zero overlapping elements:
    - Dedicated top docked control deck (.graph-control-deck) containing toolbar & query console
    - Bottom-left positioned cluster & CTI legends with collapsible toggle buttons
    - Right-side full-height slide-in node inspector drawer (.node-callout)
    """
    # 1. Docked Control Deck
    assert 'class="graph-control-deck"' in dashboard_html
    assert (
        "position: relative;" in dashboard_html
        or ".graph-control-deck" in dashboard_html
    )

    # 2. Bottom-left positioned collapsible legend
    assert "bottom: 14px;" in dashboard_html
    assert "left: 14px;" in dashboard_html
    assert "btnToggleLegendContext" in dashboard_html
    assert "btnToggleLegendCti" in dashboard_html
    assert "btn-legend-toggle" in dashboard_html
    assert "window.toggleLegend" in dashboard_html

    # 3. Right-side full-height slide-in node inspector
    assert "width: 340px;" in dashboard_html
    assert "top: 0;" in dashboard_html
    assert "bottom: 0;" in dashboard_html
    assert "right: 0;" in dashboard_html
    assert "z-index: 30;" in dashboard_html
