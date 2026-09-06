"""
Unit tests for Canvas aspect ratio and mouse normalization in site/dashboard.html.
Validates Issue #181 fixes:
1. No static height: 480px overriding flexbox container
2. ResizeObserver integration for real-time bitmap dimension sync
3. Explicit canvas.style.width and canvas.style.height synchronization
4. getNormalizedCanvasMouse coordinate scaling (prevents mouse hit-test drift)
5. Generous hitRadius for ergonomic node selection
6. transitionend listener support for header and control deck toggling
"""

import os

import pytest


@pytest.fixture
def dashboard_html_content() -> str:
    path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "site", "dashboard.html")
    )
    assert os.path.exists(path), f"dashboard.html not found at {path}"
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_canvas_container_flexbox_styles_no_static_height(
    dashboard_html_content: str,
) -> None:
    """Verify that .canvas-container does not have static height: 480px and utilizes flex: 1."""
    # Ensure static height 480px is completely removed
    assert (
        "height: 480px;" not in dashboard_html_content
    ), "Static height: 480px found in dashboard.html; should be flex: 1 and height: 100%"

    # Check that .canvas-container has flex: 1 and height: 100%
    assert ".canvas-container {" in dashboard_html_content
    assert "flex: 1;" in dashboard_html_content
    assert "height: 100%;" in dashboard_html_content


def test_resize_observer_and_style_dimension_sync(
    dashboard_html_content: str,
) -> None:
    """Verify that ResizeObserver is implemented and canvas.style dimensions are explicitly set."""
    assert "ResizeObserver" in dashboard_html_content
    assert "canvas.parentElement" in dashboard_html_content
    assert "canvas.style.width = width + 'px';" in dashboard_html_content
    assert "canvas.style.height = height + 'px';" in dashboard_html_content


def test_mouse_coordinate_normalization_and_hit_testing(
    dashboard_html_content: str,
) -> None:
    """Verify that mouse coordinates are normalized by bounding box aspect ratio and hitRadius is ergonomic."""
    assert "function getNormalizedCanvasMouse(e)" in dashboard_html_content
    assert "const scaleX = (rect.width > 0)" in dashboard_html_content
    assert "const scaleY = (rect.height > 0)" in dashboard_html_content
    assert "const hitRadius = Math.max(nodeRadius + 8, 16);" in dashboard_html_content


def test_transitionend_listeners_for_header_and_deck(
    dashboard_html_content: str,
) -> None:
    """Verify that transitionend listeners are attached to header and control deck."""
    assert (
        "dashboardHeaderEl.addEventListener('transitionend', resizeCanvas);"
        in dashboard_html_content
    )
    assert (
        "controlDeckEl.addEventListener('transitionend', resizeCanvas);"
        in dashboard_html_content
    )


def test_dynamic_boundary_padding_in_physics(
    dashboard_html_content: str,
) -> None:
    """Verify that boundary clamping in stepPhysics adapts dynamically to canvas height."""
    assert (
        "const padY = Math.min(24, Math.max(10, height * 0.05));"
        in dashboard_html_content
    )
    assert (
        "n.y = Math.max(padY, Math.min(height - padY, n.y));" in dashboard_html_content
    )
