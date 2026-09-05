"""Tests for Enterprise Cloud Console UI & Swiss Warm Design System (DSN-21 / Issue 167)."""

import re
from pathlib import Path


def test_enterprise_console_html_structure() -> None:
    """Verify site/index.html contains Azure/AWS-style Enterprise Cloud Console layout."""
    html_path = Path("site/index.html")
    assert html_path.exists(), "site/index.html must exist"
    content = html_path.read_text(encoding="utf-8")

    # 1. Global Header (48px Fixed)
    assert "console-header" in content, "Global header element required"
    assert "arXiv Security Intelligence" in content, "Brand title required"
    assert "Enterprise Portal (cs.CR)" in content, "Tenant/scope required"
    assert 'id="globalSearchInput"' in content, "Wide global search input required"
    assert "Ctrl + K" in content, "Global search keyboard shortcut badge required"
    assert 'id="systemStatusBadge"' in content, "Live system status badge required"

    # 2. Left Sidebar (Fixed 260px, Collapsible)
    assert 'id="consoleSidebar"' in content, "Sidebar element required"
    assert 'id="sidebarToggleBtn"' in content, "Sidebar collapse toggle button required"
    assert "nav-accordion" in content, "Accordion navigation required"
    assert "探索・分析 (Analytics)" in content, "Analytics group required"
    assert "脅威インテリジェンス" in content, "Threat intelligence group required"
    assert "システム運用 & 監査" in content, "Operations group required"

    # Submenu items and links
    assert 'id="navSearch"' in content, "Search nav item required"
    assert 'id="navTrends"' in content, "Trends nav item required"
    assert 'id="navGraph"' in content, "Graph nav item required"
    assert 'id="navMatrix"' in content, "ATT&CK matrix nav item required"
    assert 'id="navGaps"' in content, "Research gaps nav item required"
    assert 'id="navRules"' in content, "Inference rules nav item required"
    assert 'id="navTelemetry"' in content, "Telemetry nav item required"
    assert 'id="navMcp"' in content, "MCP sandbox nav item required"
    assert 'id="navLogs"' in content, "Audit logs nav item required"

    # 3. Main Content Area - Standard 5 Components
    # Component 1: Page Header & Action Buttons
    assert "console-page-header" in content, "Page header component required"
    assert 'id="mainPageTitle"' in content, "Main title required"
    assert 'id="refreshDataBtn"' in content, "Refresh button required"
    assert 'id="exportDataBtn"' in content, "Export button required"
    assert 'id="guideHelpBtn"' in content, "Guide/help button required"

    # Component 2: Information Banner
    assert "console-info-banner" in content, "Info banner component required"
    assert 'id="systemInfoBanner"' in content, "Info banner element required"
    assert 'id="closeBannerBtn"' in content, "Banner close button required"

    # Component 3: KPI Summary Cards with Left Color Bars
    assert "kpi-card-grid" in content, "KPI card grid required"
    assert "kpi-card-navy" in content, "Navy KPI card (Total Papers) required"
    assert "kpi-card-green" in content, "Green KPI card (Confidence) required"
    assert "kpi-card-amber" in content, "Amber KPI card (CWE) required"
    assert "kpi-card-coral" in content, "Coral KPI card (Gaps) required"
    assert 'id="totalPapersCount"' in content, "Total papers count metric required"

    # Component 4: Inline Search & Filter Deck
    assert "console-filter-deck" in content, "Filter deck component required"
    assert 'id="searchInput"' in content, "Search input required"
    assert 'id="searchBtn"' in content, "Search button required"
    assert 'id="clearFiltersBtn"' in content, "Clear filter button required"
    assert 'id="tagFilters"' in content, "Tag filters container required"
    assert 'id="pageSizeSelect"' in content, "Page size select required"

    # Component 5: Resource Data List & Results
    assert 'id="resultsCount"' in content, "Results count required"
    assert 'id="searchTime"' in content, "Search time elapsed tag required"
    assert 'id="resultsGrid"' in content, "Results grid required"
    assert 'id="loadMoreContainer"' in content, "Load more container required"
    assert 'id="loadMoreBtn"' in content, "Load more button required"

    # Retain Modals & Tabs
    assert 'id="searchTab"' in content, "Search tab container required"
    assert 'id="trendsTab"' in content, "Trends tab container required"
    assert 'id="mcpTab"' in content, "MCP tab container required"
    assert 'id="paperModal"' in content, "Paper OKF modal required"


def test_enterprise_design_system_tokens() -> None:
    """Verify site/style.css defines Swiss Warm Enterprise tokens (DSN-21)."""
    css_path = Path("site/style.css")
    assert css_path.exists(), "site/style.css must exist"
    css_text = css_path.read_text(encoding="utf-8")

    # Tokens check
    expected_tokens = [
        ("--console-bg-canvas", "#f4efe6"),
        ("--console-bg-panel", "#ebe5d8"),
        ("--console-bg-subpanel", "#dfd8c9"),
        ("--console-fg-primary", "#2b2b2b"),
        ("--console-fg-muted", "#6b665c"),
        ("--console-border-dark", "#2b2b2b"),
        ("--console-accent-navy", "#3d5a80"),
        ("--console-accent-green", "#3a7d44"),
        ("--console-accent-amber", "#d97706"),
        ("--console-accent-coral", "#e0533c"),
    ]
    for token_name, expected_val in expected_tokens:
        assert (
            token_name in css_text
        ), f"Token {token_name} must be defined in style.css"
        assert (
            expected_val in css_text
        ), f"Token value {expected_val} must be defined in style.css"

    # Active nav 3px border-left check
    assert (
        "border-left: 3px solid" in css_text
    ), "Active nav item must have 3px accent left bar"

    # KPI Card Left Color Bars check
    assert ".kpi-card-navy::before" in css_text, "Navy KPI card accent bar required"
    assert ".kpi-card-green::before" in css_text, "Green KPI card accent bar required"
    assert ".kpi-card-amber::before" in css_text, "Amber KPI card accent bar required"
    assert ".kpi-card-coral::before" in css_text, "Coral KPI card accent bar required"


def test_enterprise_console_interaction_scripts() -> None:
    """Verify site/app.js implements console interactions (shortcuts, accordion, routing)."""
    app_js_path = Path("site/app.js")
    assert app_js_path.exists(), "site/app.js must exist"
    js_text = app_js_path.read_text(encoding="utf-8")

    # Keyboard shortcut (Ctrl+K or /)
    assert "globalSearchInput" in js_text, "globalSearchInput must be handled in app.js"
    assert re.search(
        r"e\.key.*['\"]k['\"]", js_text, re.IGNORECASE
    ), "Ctrl+K shortcut required"

    # Sidebar collapse & accordion toggle
    assert "sidebarToggleBtn" in js_text, "Sidebar toggle handled in app.js"
    assert "nav-group-header" in js_text, "Accordion header handled in app.js"

    # Hash routing
    assert "hashchange" in js_text, "Hash routing event listener required"
    assert "popstate" in js_text, "Popstate history event listener required"
    assert "productTab" in js_text, "Product tab routing supported"
    assert "systemTab" in js_text, "System tab routing supported"
    assert "supervisorTab" in js_text, "Supervisor tab routing supported"


def test_ported_product_system_supervisor_views() -> None:
    """Verify ported tabs, canvas charts, and telemetry tables exist in index.html (Issue 169)."""
    content = Path("site/index.html").read_text(encoding="utf-8")

    # 1. Navigation items
    assert 'id="navProduct"' in content, "navProduct nav item required"
    assert 'id="navSystem"' in content, "navSystem nav item required"
    assert 'id="navSupervisor"' in content, "navSupervisor nav item required"

    # 2. Main content sections
    assert 'id="productTab"' in content, "productTab section required"
    assert 'id="systemTab"' in content, "systemTab section required"
    assert 'id="supervisorTab"' in content, "supervisorTab section required"

    # 3. Canvas and visual elements
    assert 'id="hopCanvas"' in content, "Hop budget canvas required"
    assert 'id="walkVsFlatCanvas"' in content, "Walk vs Flat canvas required"
    assert 'id="traversalMatrix"' in content, "Traversal matrix container required"
    assert 'id="pipelineBar"' in content, "Pipeline status bar required"

    # 4. Storage ledger and supervisor top tables
    assert 'id="databaseTablesTableBody"' in content, "Database tables body required"
    assert (
        'id="supervisorWorkersTableBody"' in content
    ), "Supervisor workers body required"


def test_ported_telemetry_script_handlers() -> None:
    """Verify site/app.js contains calculation, rendering, and SSE routines (Issue 169)."""
    js_text = Path("site/app.js").read_text(encoding="utf-8")

    # Routing and tab config
    assert "TAB_CONFIG" in js_text, "TAB_CONFIG object required"
    assert "productTab" in js_text, "productTab in TAB_CONFIG required"
    assert "systemTab" in js_text, "systemTab in TAB_CONFIG required"
    assert "supervisorTab" in js_text, "supervisorTab in TAB_CONFIG required"

    # Analytics routines
    assert "calculateAndDrawHopHistogram" in js_text, "Hop histogram routine required"
    assert "updateRealEdgeLedger" in js_text, "Edge ledger routine required"
    assert "drawWalkChart" in js_text, "Walk chart routine required"
    assert "renderTraversalMatrix" in js_text, "Traversal matrix routine required"

    # Telemetry and SSE streaming
    assert "updateDatabaseMetrics" in js_text, "Database metrics updater required"
    assert "updateSupervisorFromStream" in js_text, "Supervisor updater required"
    assert "syncConsoleTelemetry" in js_text, "Console telemetry sync required"
    assert "initSseLiveStream" in js_text, "SSE live stream initializer required"


def test_enterprise_console_help_drawer() -> None:
    """Verify Help & Guide Drawer implementation matching dashboard.html design and interactions (Issue 171)."""
    index_html = Path("site/index.html").read_text(encoding="utf-8")
    style_css = Path("site/style.css").read_text(encoding="utf-8")
    app_js = Path("site/app.js").read_text(encoding="utf-8")

    # 1. HTML elements & structure in index.html
    assert 'id="consoleHelpOverlay"' in index_html, "Help overlay required"
    assert 'class="help-overlay"' in index_html, "Help overlay class required"
    assert 'id="consoleHelpDrawer"' in index_html, "Help drawer required"
    assert 'class="help-drawer"' in index_html, "Help drawer class required"
    assert "drawer-header" in index_html, "Drawer header required"
    assert "btn-drawer-close" in index_html, "Drawer close button required"
    assert "drawer-content" in index_html, "Drawer content container required"
    assert "guide-section" in index_html, "Guide section container required"
    assert "guide-table" in index_html, "Guide table required"

    # Guide Content Sections
    assert "基本マウス &amp; キーボードショートカット" in index_html
    assert "統合コンソールの主要ワークスペース" in index_html
    assert "CTI ナレッジグラフとの連携" in index_html
    assert "データ保全 &amp; Google OKF v0.2 仕様" in index_html

    # Header help button trigger
    assert (
        'onclick="toggleConsoleHelpDrawer()"' in index_html
        or "toggleConsoleHelpDrawer" in app_js
    )

    # 2. CSS Rules in style.css (Dark Glassmorphic Drawer)
    assert ".help-overlay" in style_css
    assert ".help-drawer" in style_css
    assert "backdrop-filter: blur(24px)" in style_css
    assert "box-shadow: -12px 0 40px" in style_css
    assert "transform: translateX(100%)" in style_css
    assert ".help-drawer.active" in style_css
    assert "transform: translateX(0)" in style_css

    # 3. JavaScript interaction in app.js
    assert "window.toggleConsoleHelpDrawer" in app_js
    assert "window.closeConsoleHelpDrawer" in app_js
    assert (
        "consoleHelpDrawer.classList.toggle" in app_js
        or "classList.add('active')" in app_js
    )
    assert "e.key === 'Escape'" in app_js
    assert "e.key === '?'" in app_js
