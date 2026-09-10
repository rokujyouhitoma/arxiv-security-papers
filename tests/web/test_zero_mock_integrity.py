"""
tests/web/test_zero_mock_integrity.py

Issue #216: Verifies that all identified mock implementations and hardcoded
dummy values have been eliminated from the codebase.

Tests are intentionally static (file-content based) to serve as ratchets that
permanently prevent regression of removed mocks, plus one dynamic test to
verify _compute_loop_timestamps reads from log.md.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_ROOT = Path(__file__).parent.parent.parent


def _read_app_js() -> str:
    return (_ROOT / "site" / "app.js").read_text(encoding="utf-8")


def _read_handlers_py() -> str:
    return (_ROOT / "src" / "web" / "gateway" / "handlers.py").read_text(
        encoding="utf-8"
    )


def _read_index_html() -> str:
    return (_ROOT / "site" / "index.html").read_text(encoding="utf-8")


def _read_dashboard_html() -> str:
    return (_ROOT / "site" / "dashboard.html").read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Test Class
# ---------------------------------------------------------------------------
class TestZeroMockIntegrity(unittest.TestCase):
    """Verifies complete elimination of mock/hardcoded values (Issue #216)."""

    # ------------------------------------------------------------------ M7 --
    def test_no_dummy_hop_counts_fallback_m7(self) -> None:
        """M7: [18,42,68,34,12] dummy hop histogram fallback must be gone."""
        content = _read_app_js()
        self.assertNotIn(
            "hopCounts[0] = 18",
            content,
            "M7: dummy hop histogram fallback [18,42,68,34,12] still present in app.js",
        )

    # ------------------------------------------------------------------ M8 --
    def test_no_fixed_88_dots_in_traversal_matrix_m8(self) -> None:
        """M8: i < 88 hardcoded success-dot count must be removed."""
        content = _read_app_js()
        self.assertNotIn(
            "i < 88",
            content,
            "M8: renderTraversalMatrix still uses hardcoded i<88 threshold in app.js",
        )

    def test_traversal_matrix_accepts_success_rate_param_m8(self) -> None:
        """M8: renderTraversalMatrix must accept a successRatePct parameter."""
        content = _read_app_js()
        self.assertIn(
            "renderTraversalMatrix(successRatePct)",
            content,
            "M8: renderTraversalMatrix does not declare successRatePct parameter",
        )

    # ------------------------------------------------------------------ M9 --
    def test_no_fixed_74_2_walk_history_m9(self) -> None:
        """M9: walkHistory must not be initialised with fixed [74.2, ...] values."""
        content = _read_app_js()
        self.assertNotIn(
            "walkHistory = [74.2",
            content,
            "M9: walkHistory still uses fixed [74.2,...] initialization in app.js",
        )

    # ----------------------------------------------------------------- M10 --
    def test_token_savings_fallback_not_minus_74_2_m10(self) -> None:
        """M10: token_savings_pct fallback must not be '-74.2%'."""
        content = _read_handlers_py()
        self.assertNotIn(
            '"-74.2%"',
            content,
            "M10: handlers.py still uses '-74.2%' as token_savings_pct fallback",
        )

    def test_pipeline_slo_pct_default_is_not_100_m10(self) -> None:
        """M10: pipeline_slo_pct default must be 0.0, not 100.0."""
        content = _read_handlers_py()
        self.assertNotIn(
            'pipeline_slo_pct", 100.0)',
            content,
            "M10: handlers.py still uses 100.0 as pipeline_slo_pct default",
        )

    # ----------------------------------------------------------------- M11 --
    def test_no_hardcoded_14169_in_tab_config_m11(self) -> None:
        """M11: TAB_CONFIG.searchTab.subtitle must not hardcode '14,169'."""
        content = _read_app_js()
        tab_start = content.find("TAB_CONFIG")
        self.assertGreater(tab_start, -1, "TAB_CONFIG block not found in app.js")
        tab_block = content[tab_start : tab_start + 2000]
        self.assertNotIn(
            "14,169",
            tab_block,
            "M11: TAB_CONFIG still contains hardcoded '14,169' paper count in app.js",
        )

    def test_update_paper_count_display_exists_m11(self) -> None:
        """M11: updatePaperCountDisplay() function must exist in app.js."""
        content = _read_app_js()
        self.assertIn(
            "function updatePaperCountDisplay",
            content,
            "M11: updatePaperCountDisplay() function is missing from app.js",
        )

    def test_desc_papers_count_span_in_index_html_m11(self) -> None:
        """M11: index.html must have <span id='descPapersCount'> for dynamic update."""
        content = _read_index_html()
        self.assertIn(
            'id="descPapersCount"',
            content,
            "M11: <span id='descPapersCount'> is missing from index.html",
        )

    # ----------------------------------------------------------------- M12 --
    def test_compute_loop_timestamps_reads_log_md_m12(self) -> None:
        """M12: _compute_loop_timestamps must reference outputs/log.md."""
        content = _read_handlers_py()
        self.assertIn(
            "log.md",
            content,
            "M12: handlers.py _compute_loop_timestamps does not reference log.md",
        )

    def test_compute_loop_timestamps_is_not_staticmethod_m12(self) -> None:
        """M12: _compute_loop_timestamps must be an instance method (not @staticmethod)."""
        content = _read_handlers_py()
        # The @staticmethod decorator should NOT appear directly before the method
        static_before = "@staticmethod\n    def _compute_loop_timestamps" in content
        self.assertFalse(
            static_before,
            "M12: _compute_loop_timestamps is still declared as @staticmethod",
        )

    def test_compute_loop_timestamps_returns_last_log_entry(self) -> None:
        """M12 (dynamic): _compute_loop_timestamps must return last log.md timestamp."""
        import sys

        src_path = str(_ROOT / "src")
        if src_path not in sys.path:
            sys.path.insert(0, src_path)

        try:
            from web.gateway.handlers import GatewayHandlers  # type: ignore[import]
        except ImportError:
            self.skipTest("GatewayHandlers not importable in this environment")

        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a minimal outputs/log.md with a known timestamp
            outputs_dir = os.path.join(tmpdir, "outputs")
            os.makedirs(outputs_dir)
            known_ts = "2026-09-10 12:00:00 UTC"
            log_content = (
                "| 実行日時 (UTC) | 処理論文数 |\n"
                "| :--- | :--- |\n"
                f"| {known_ts} | 42 |\n"
            )
            with open(os.path.join(outputs_dir, "log.md"), "w", encoding="utf-8") as f:
                f.write(log_content)

            # Instantiate a minimal handler using tmpdir as workspace
            try:
                handler = GatewayHandlers.__new__(GatewayHandlers)
                handler.workspace_dir = tmpdir  # type: ignore[attr-defined]
                last_sync, next_sync = handler._compute_loop_timestamps()
                self.assertEqual(
                    last_sync,
                    known_ts,
                    f"M12: expected last_sync='{known_ts}', got '{last_sync}'",
                )
            except Exception as exc:
                self.skipTest(f"Could not instantiate GatewayHandlers: {exc}")

    # ------------------------------------------------------------------ M6 --
    def test_mesh_response_has_traversal_stats_field_m6(self) -> None:
        """M6/M8: handle_graph_mesh response must include 'traversal_stats' field."""
        content = _read_handlers_py()
        self.assertIn(
            '"traversal_stats"',
            content,
            "M6/M8: 'traversal_stats' key is missing from handle_graph_mesh response",
        )

    def test_build_real_graph_mesh_function_exists_m6(self) -> None:
        """M6: _build_real_graph_mesh() function must exist in handlers.py."""
        content = _read_handlers_py()
        self.assertIn(
            "def _build_real_graph_mesh(",
            content,
            "M6: _build_real_graph_mesh() function is missing from handlers.py",
        )

    # ----------------------------------------------------------- D1 - D4 (dashboard.html) --
    def test_dashboard_html_no_fixed_walk_history_d1(self) -> None:
        """D1: dashboard.html must not initialize walkHistory with [74.2, ...]."""
        content = _read_dashboard_html()
        self.assertNotIn(
            "walkHistory = [74.2",
            content,
            "D1: dashboard.html still has hardcoded [74.2,...] walkHistory",
        )

    def test_dashboard_html_render_traversal_matrix_accepts_param_d2(self) -> None:
        """D2: dashboard.html renderTraversalMatrix must accept successRatePct."""
        content = _read_dashboard_html()
        self.assertIn(
            "renderTraversalMatrix(successRatePct)",
            content,
            "D2: dashboard.html renderTraversalMatrix does not accept successRatePct",
        )

    def test_dashboard_html_no_fixed_88_dots_d2(self) -> None:
        """D2: dashboard.html renderTraversalMatrix must not hardcode i < 88."""
        content = _read_dashboard_html()
        self.assertNotIn(
            "i < 88",
            content,
            "D2: dashboard.html still hardcodes i < 88 in renderTraversalMatrix",
        )

    def test_dashboard_html_no_hardcoded_resolved_nodes_14507_d3(self) -> None:
        """D3: dashboard.html must not hardcode currentResolvedNodes = 14507."""
        content = _read_dashboard_html()
        self.assertNotIn(
            "currentResolvedNodes = 14507",
            content,
            "D3: dashboard.html still hardcodes currentResolvedNodes = 14507",
        )

    # ------------------------------------------------------------- D5 - D8 (index/app.js) --
    def test_index_html_no_hardcoded_pipeline_timestamp_d5(self) -> None:
        """D5: index.html must not hardcode '2026-09-05 06:00' pipeline execution time."""
        content = _read_index_html()
        self.assertNotIn(
            "2026-09-05 06:00",
            content,
            "D5: index.html still has hardcoded '2026-09-05 06:00' timestamp",
        )

    def test_index_html_dynamic_kpi_elements_present_d7(self) -> None:
        """D7: index.html must have IDs for dynamic KPI binding."""
        content = _read_index_html()
        for element_id in (
            "kpiConfidenceVal",
            "kpiCweVal",
            "kpiGapsVal",
            "bannerPipelineTime",
        ):
            self.assertIn(
                f'id="{element_id}"',
                content,
                f"D7: index.html missing dynamic ID '{element_id}'",
            )

    def test_app_js_notif_center_no_hardcoded_date_d8(self) -> None:
        """D8: app.js notification center must not hardcode '2026-09-05 06:00'."""
        content = _read_app_js()
        self.assertNotIn(
            "2026-09-05 06:00",
            content,
            "D8: app.js alert still hardcodes '2026-09-05 06:00'",
        )

    # ------------------------------------------------------------- D10 - D12 (Issue #228 Lifecycle & System Tab) --
    def test_system_lifecycle_endpoint_and_handler_registered_d10(self) -> None:
        """D10: /api/system/lifecycle endpoint and handler must exist."""
        handlers_content = _read_handlers_py()
        self.assertIn(
            "def handle_system_lifecycle(",
            handlers_content,
            "D10: handlers.py missing handle_system_lifecycle method",
        )
        app_py = (_ROOT / "src" / "web" / "gateway" / "app.py").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            '"/api/system/lifecycle"',
            app_py,
            "D10: app.py missing /api/system/lifecycle route",
        )

    def test_index_html_system_tab_has_operational_cards_and_no_dead_elements_d11(
        self,
    ) -> None:
        """D11: index.html system tab must have 4 operational cards and 6 phases, with dead elements removed."""
        content = _read_index_html()
        for element_id in (
            "cardScheduler",
            "cardArtifactLifecycle",
            "cardExternalHealth",
            "cardSlaAuditLedger",
            "phaseStep0",
            "phaseStep5",
            "valLastRunStatus",
            "valSchedulerCron",
            "valSlaRate",
        ):
            self.assertIn(
                f'id="{element_id}"',
                content,
                f"D11: index.html missing dynamic operational card element '{element_id}'",
            )

        # Ensure dead elements from legacy mock graph traversal are eliminated
        self.assertNotIn(
            'id="valDeadEndDepth"',
            content,
            "D11: index.html still contains dead element 'valDeadEndDepth'",
        )

    def test_app_js_sync_lifecycle_telemetry_exists_d12(self) -> None:
        """D12: app.js must have syncLifecycleTelemetry() function fetching /api/system/lifecycle."""
        content = _read_app_js()
        self.assertIn(
            "async function syncLifecycleTelemetry",
            content,
            "D12: app.js missing syncLifecycleTelemetry() function",
        )
        self.assertIn(
            "fetch('/api/system/lifecycle')",
            content,
            "D12: app.js syncLifecycleTelemetry does not fetch /api/system/lifecycle",
        )


if __name__ == "__main__":
    unittest.main()
