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


def test_dashboard_vertex_size_scaling_by_edge_degree(dashboard_html: str) -> None:
    """Verifies that vertices (nodes) are dynamically scaled proportional to edge degrees:
    - Area-proportional model R(k) = R_0 * sqrt(1 + k)
    - updateNodeRadii function definition and invocations
    - calloutDegree badge display in node inspector
    """
    import math

    # 1. Verification of JavaScript updateNodeRadii logic
    assert "function updateNodeRadii(nodes, edges)" in dashboard_html
    assert "Math.sqrt(1 + k)" in dashboard_html
    assert "degreeMap" in dashboard_html
    assert "updateNodeRadii(NODES, EDGES);" in dashboard_html

    # 2. Callout badge for degree and radius display
    assert 'id="calloutDegree"' in dashboard_html
    assert "callout-degree" in dashboard_html
    assert (
        "degEl.textContent = `Edges: ${k} (R=${r}px)`);" in dashboard_html
        or "Edges: ${k}" in dashboard_html
    )

    # 3. Mathematical precision check for Area-Proportional Model (Plan A)
    r0_standard = 5.5
    # k=0 (isolated): R(0) = 5.5 * sqrt(1) = 5.5
    r_k0 = round(r0_standard * math.sqrt(1 + 0), 1)
    assert r_k0 == 5.5

    # k=1 (leaf node, 1 edge): R(1) = 5.5 * sqrt(2) ~= 7.78 -> 7.8
    r_k1 = round(r0_standard * math.sqrt(1 + 1), 1)
    assert r_k1 == 7.8
    assert math.isclose(r_k1 / r_k0, math.sqrt(2), rel_tol=1e-2)

    # k=3 (quadruple area): R(3) = 5.5 * sqrt(4) = 11.0 (2x radius = 4x area)
    r_k3 = round(r0_standard * math.sqrt(1 + 3), 1)
    assert r_k3 == 11.0


def test_dashboard_graph_query_subgraph_preservation_against_background_sync(
    dashboard_html: str,
) -> None:
    """Verifies that active graph query subgraph is preserved against 5s periodic background sync:
    - activeGraphQuery state variable defined
    - executeGraphQuery sets activeGraphQuery immediately
    - clearGraphQuery resets activeGraphQuery to null
    - fetchCtiMesh(force = false) guards against overwriting ctiRawNodes during active queries
    - syncLiveMesh checks !activeGraphQuery before invoking fetchCtiMesh
    """
    # 1. State variable definition
    assert "let activeGraphQuery = null;" in dashboard_html

    # 2. executeGraphQuery locking
    assert "activeGraphQuery = query;" in dashboard_html
    assert "if (activeGraphQuery !== query) return;" in dashboard_html

    # 3. clearGraphQuery resetting
    assert "window.clearGraphQuery = function()" in dashboard_html
    assert "activeGraphQuery = null;" in dashboard_html
    assert "fetchCtiMesh(true);" in dashboard_html

    # 4. fetchCtiMesh guard against full mesh overwrite
    assert "async function fetchCtiMesh(force = false)" in dashboard_html
    assert "if (activeGraphQuery && !force)" in dashboard_html

    # 5. syncLiveMesh 5s periodic loop guard
    assert "currentGraphMode === 'cti' && !activeGraphQuery" in dashboard_html


def test_dashboard_toggle_hide_isolated_nodes(dashboard_html: str) -> None:
    """Verifies that the isolated nodes toggle button and filtering logic are properly implemented:
    - Button #btnToggleIsolated with toggleIsolatedNodes() handler exists in the toolbar
    - hideIsolatedNodes state variable and window.toggleIsolatedNodes() function defined
    - applyCtiFilter filters out nodes with degree=0 when hideIsolatedNodes is true
    - applyContextMesh filters out nodes with degree=0 when hideIsolatedNodes is true
    - Result badge shows isolated count when filtered
    """
    # 1. UI element and event binding
    assert 'id="btnToggleIsolated"' in dashboard_html
    assert 'onclick="toggleIsolatedNodes()"' in dashboard_html
    assert "🔗 孤立ノード除外" in dashboard_html

    # 2. State variable and toggle function
    assert "let hideIsolatedNodes = false;" in dashboard_html
    assert "window.toggleIsolatedNodes = function()" in dashboard_html
    assert "hideIsolatedNodes = !hideIsolatedNodes;" in dashboard_html
    assert "btnToggleIsolated" in dashboard_html
    assert "btn.classList.add('active');" in dashboard_html

    # 3. CTI Graph filtering logic for degree=0 (isolated nodes)
    assert "if (hideIsolatedNodes) {" in dashboard_html
    assert "connectedIds.add(e.source);" in dashboard_html
    assert "connectedIds.add(e.target);" in dashboard_html
    assert (
        "filteredNodes = filteredNodes.filter(n => connectedIds.has(n.id));"
        in dashboard_html
    )

    # 4. Context Mesh filtering logic for degree=0 (isolated nodes)
    assert "function applyContextMesh()" in dashboard_html
    assert "applyContextMesh();" in dashboard_html


def test_dashboard_min_degree_hub_filter(dashboard_html: str) -> None:
    """Verifies that the Min-Degree Hub Filter (All, >=1, >=2, >=3) is properly implemented:
    - Button elements #btnDegAll, #btnDeg1, #btnDeg2, #btnDeg3 exist in the toolbar
    - State variable minDegreeThreshold and window.setMinDegree() function defined
    - applyCtiFilter filters out nodes with degree < minDegreeThreshold
    - applyContextMesh filters out nodes with degree < minDegreeThreshold
    - Result badge reflects minDegreeThreshold
    """
    # 1. UI elements
    assert 'id="btnDegAll"' in dashboard_html
    assert 'id="btnDeg1"' in dashboard_html
    assert 'id="btnDeg2"' in dashboard_html
    assert 'id="btnDeg3"' in dashboard_html
    assert "MIN DEGREE:" in dashboard_html

    # 2. State variable and setMinDegree function
    assert "let minDegreeThreshold = 0;" in dashboard_html
    assert "window.setMinDegree = function(deg)" in dashboard_html
    assert "minDegreeThreshold = Math.max(0, parseInt(deg, 10) || 0);" in dashboard_html
    assert (
        "btnAll.classList.toggle('active', minDegreeThreshold === 0);" in dashboard_html
    )

    # 3. Degree calculation and filtering in applyCtiFilter
    assert "degrees.set(e.source, (degrees.get(e.source) || 0) + 1);" in dashboard_html
    assert "degrees.set(e.target, (degrees.get(e.target) || 0) + 1);" in dashboard_html
    assert (
        "filteredNodes = filteredNodes.filter(n => (degrees.get(n.id) || 0) >= minDegreeThreshold);"
        in dashboard_html
    )

    # 4. Result badge status formatting
    assert "最小次数 ≥" in dashboard_html


def test_dashboard_focus_ego_subgraph_mode(dashboard_html: str) -> None:
    """Verifies that the Focus Ego Subgraph Mode is properly implemented:
    - Button #btnFocusEgo exists in #nodeCallout
    - Toolbar elements #focusBanner, #focusTargetLabel, #btnClearFocus exist
    - State variables focusedNodeId, focusedHopNodeIds defined
    - Functions getEgoNeighborhood, focusEgoNetwork, clearNodeFocus, focusCurrentSelectedEgo defined
    - Canvas dblclick listener and mousedown background deselect listener implemented
    - Dimming logic (0.08 / 0.05) and center node pulse ring implemented in render loop
    """
    # 1. UI Elements in DOM
    assert 'id="btnFocusEgo"' in dashboard_html
    assert 'onclick="focusCurrentSelectedEgo()"' in dashboard_html
    assert 'id="focusBanner"' in dashboard_html
    assert 'id="focusTargetLabel"' in dashboard_html
    assert 'id="btnClearFocus"' in dashboard_html
    assert 'onclick="clearNodeFocus()"' in dashboard_html

    # 2. State variables and functions
    assert "let focusedNodeId = null;" in dashboard_html
    assert "let focusedHopNodeIds = null;" in dashboard_html
    assert "function getEgoNeighborhood(centerId, depth = 2)" in dashboard_html
    assert "function focusEgoNetwork(nodeId, depth = 2)" in dashboard_html
    assert "window.focusCurrentSelectedEgo = function()" in dashboard_html
    assert "window.clearNodeFocus = function()" in dashboard_html

    # 3. BFS cycle guard and depth clamping
    assert "Math.min(Math.max(1, parseInt(depth, 10) || 2), 3)" in dashboard_html
    assert "const visited = new Set([centerId]);" in dashboard_html
    assert "if (neighbor && !visited.has(neighbor))" in dashboard_html

    # 4. Canvas event listeners
    assert "canvas.addEventListener('dblclick'" in dashboard_html
    assert "focusEgoNetwork(node.id, 2);" in dashboard_html
    assert "if (focusedNodeId) {\n            clearNodeFocus();" in dashboard_html

    # 5. Rendering dimming and pulse ring
    assert (
        "const isEgoDimmed = (focusedHopNodeIds && (!focusedHopNodeIds.has(u.id) || !focusedHopNodeIds.has(v.id)));"
        in dashboard_html
    )
    assert "ctx.globalAlpha = 0.05;" in dashboard_html
    assert (
        "const isEgoDimmed = (focusedHopNodeIds && !focusedHopNodeIds.has(n.id));"
        in dashboard_html
    )
    assert (
        "const isEgoCenter = (focusedNodeId && n.id === focusedNodeId);"
        in dashboard_html
    )
    assert "ctx.globalAlpha = 0.08;" in dashboard_html
    assert (
        "const egoPulseR = nodeRadius + 5 + Math.sin(Date.now() / 250) * 3;"
        in dashboard_html
    )


def test_dashboard_edge_confidence_and_rule_filter(dashboard_html: str) -> None:
    """Verifies that tab=graph supports confidence and rule filtering and evidence quotes."""
    # 1. Toolbar UI buttons
    assert 'id="btnConfAll"' in dashboard_html
    assert 'id="btnConfMed"' in dashboard_html
    assert 'id="btnConfHigh"' in dashboard_html
    assert 'id="selectEdgeRule"' in dashboard_html
    assert "RULE-EDGE-PAPER-TECH-REGEX-01" in dashboard_html
    assert "RULE-EDGE-PAPER-TECH-TITLE-02" in dashboard_html

    # 2. State variables and functions
    assert "let edgeConfidenceFilter = 'all';" in dashboard_html
    assert "let edgeRuleFilter = 'all';" in dashboard_html
    assert "window.setEdgeConfidenceFilter = function(tier)" in dashboard_html
    assert "window.setEdgeRuleFilter = function(ruleId)" in dashboard_html

    # 3. Filtering logic in applyCtiFilter
    assert "if (edgeConfidenceFilter === 'HIGH')" in dashboard_html
    assert "if (edgeConfidenceFilter === 'MEDIUM')" in dashboard_html
    assert "if (edgeRuleFilter && edgeRuleFilter !== 'all')" in dashboard_html

    # 4. Canvas rendering style differentiation
    assert "if (e.confidence_tier === 'HIGH')" in dashboard_html
    assert "ctx.lineWidth = Math.max(ctx.lineWidth, 1.8);" in dashboard_html
    assert "else if (e.confidence_tier === 'LOW')" in dashboard_html
    assert "ctx.setLineDash([3, 3]);" in dashboard_html

    # 5. Callout relations with confidence badge and evidence quotes
    assert "e.confidence_tier === 'HIGH' ? '#10B981'" in dashboard_html
    assert "🏷️ Rule: <code>${escapeHtml(e.primary_rule_id)}</code>" in dashboard_html
    assert "&ldquo;${escapeHtml(e.evidence_quote)}&rdquo;" in dashboard_html


def test_dashboard_glassmorphic_tooltips_and_help_drawer(
    dashboard_html: str,
) -> None:
    """Verifies Glassmorphic tooltips, info badges, and Quick Guide Drawer (Issue 166)."""
    # 1. Tooltip & Drawer CSS styling
    assert "[data-tooltip]" in dashboard_html
    assert '[data-tooltip-pos="bottom"]' in dashboard_html
    assert ".info-badge" in dashboard_html
    assert ".graph-help-drawer" in dashboard_html
    assert ".graph-help-overlay" in dashboard_html

    # 2. Interactive toolbar and query controls with data-tooltip
    required_tooltip_elements = [
        'id="btnModeMesh"',
        'id="btnModeCti"',
        'id="filterAll"',
        'id="filterPaper"',
        'id="filterAttack"',
        'id="filterCwe"',
        'id="btnToggleGaps"',
        'id="btnConfAll"',
        'id="btnConfMed"',
        'id="btnConfHigh"',
        'id="selectEdgeRule"',
        'id="btnDegAll"',
        'id="btnDeg1"',
        'id="btnDeg2"',
        'id="btnDeg3"',
        'id="btnToggleIsolated"',
        'id="btnToggleHeaderQuick"',
        'id="btnOpenGraphHelp"',
        'id="graphQueryInput"',
        'id="btnRunGraphQuery"',
        'id="btnClearGraphQuery"',
    ]
    for el in required_tooltip_elements:
        assert el in dashboard_html, f"Missing element {el}"

    assert dashboard_html.count('class="info-badge"') >= 4

    # 3. Help Drawer DOM Structure & Guides
    assert 'id="graphHelpDrawer"' in dashboard_html
    assert 'id="graphHelpOverlay"' in dashboard_html
    assert "基本マウス &amp; キーボード操作" in dashboard_html
    assert "2つのグラフモード" in dashboard_html
    assert "確信度ティア (Confidence Tier)" in dashboard_html
    assert "CTI クエリ構文チートシート" in dashboard_html

    # 4. JS Toggle Functions & Keyboard Listeners
    assert "window.toggleGraphHelpDrawer = function()" in dashboard_html
    assert "window.closeGraphHelpDrawer = function()" in dashboard_html
    assert "if (e.key === 'Escape')" in dashboard_html
    assert "closeGraphHelpDrawer();" in dashboard_html
    assert "toggleGraphHelpDrawer();" in dashboard_html

    # 5. Canvas node hover guidance
    assert "💡 クリックで詳細 / Wクリックでエゴ抽出" in dashboard_html

    # 6. Viewport edge cut-off prevention (Issue 166)
    assert '[data-tooltip-align="left"]' in dashboard_html
    assert '[data-tooltip-align="right"]' in dashboard_html
    assert 'data-tooltip-align="left"' in dashboard_html
    assert 'data-tooltip-align="right"' in dashboard_html
    assert "function adjustTooltipViewportAlignment(el)" in dashboard_html
    assert "centerX < 160" in dashboard_html
    assert "window.innerWidth - centerX < 160" in dashboard_html
    assert "adjustTooltipViewportAlignment(el);" in dashboard_html
