#!/usr/bin/env python3
"""
Unit tests for Pre-Aggregated Analytics Engine & High-Speed Storage (Issue 096).
Verifies atomic snapshot saving, SQLite migrations, batch metric calculations, and CLI.
"""

import os
import tempfile

from analytics.aggregator import AnalyticsAggregator
from analytics.cli import main as cli_main
from analytics.storage import AnalyticsStorage


def test_analytics_storage_atomic_snapshot_and_load() -> None:
    """Verifies atomic snapshot persistence and fast O(1) loading."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        storage = AnalyticsStorage(workspace_dir=tmp_dir)

        # 1. Verify None before any snapshot
        assert storage.load_latest_metrics() is None

        # 2. Save snapshot
        sample_data = {
            "token_cost_savings_usd": 101.5,
            "token_savings_pct": "-74.2%",
            "top_threat_vectors": [
                {
                    "name": "Prompt Injection & LLM Security",
                    "category": "LLM Security",
                    "count": 4586,
                    "prev_count": 1991,
                    "growth": "+30.3%",
                }
            ],
            "latency_p95_ms": 74.82,
            "ontology_density": 0.048,
            "pipeline_slo_pct": 99.98,
        }
        saved_path = storage.save_snapshot(sample_data)
        assert os.path.exists(saved_path)

        # 3. Load snapshot and verify equality
        loaded = storage.load_latest_metrics()
        assert loaded is not None
        assert loaded["token_cost_savings_usd"] == 101.5
        assert len(loaded["top_threat_vectors"]) == 1
        assert (
            loaded["top_threat_vectors"][0]["name"] == "Prompt Injection & LLM Security"
        )


def test_analytics_storage_sqlite_migrations_and_history() -> None:
    """Verifies self-applying SQLite migrations and query execution."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        storage = AnalyticsStorage(workspace_dir=tmp_dir)
        assert os.path.exists(storage.db_path)

        # Save snapshot to trigger DB insertion
        sample = {
            "token_cost_savings_usd": 22.87,
            "top_threat_vectors": [
                {
                    "name": "Side-Channel & Cryptanalysis",
                    "category": "Cryptography",
                    "count": 783,
                    "prev_count": 361,
                    "growth": "+16.9%",
                }
            ],
        }
        storage.save_snapshot(sample)

        # Query SQLite tables directly
        with storage._get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT * FROM threat_trends WHERE name=?",
                ("Side-Channel & Cryptanalysis",),
            )
            row = cur.fetchone()
            assert row is not None
            assert row["category"] == "Cryptography"
            assert row["count"] == 783
            assert row["growth_pct"] == 16.9

            cur.execute(
                "SELECT * FROM strategic_kpis WHERE kpi_key=?",
                ("token_cost_savings_usd",),
            )
            kpi_row = cur.fetchone()
            assert kpi_row is not None
            assert kpi_row["num_value"] == 22.87

            cur.execute("SELECT COUNT(*) FROM metrics_history")
            h_count = cur.fetchone()[0]
            assert h_count >= 1


def test_analytics_aggregator_end_to_end() -> None:
    """Verifies that AnalyticsAggregator aggregates metrics from repository state."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        # Create mock OKF papers directory
        okf_dir = os.path.join(tmp_dir, "outputs", "okf_papers", "2026-08-28")
        os.makedirs(okf_dir, exist_ok=True)

        paper1_path = os.path.join(okf_dir, "2608.00001.md")
        with open(paper1_path, "w", encoding="utf-8") as f:
            f.write("# Paper 1\nPrompt injection attacks on large language models.")

        paper2_path = os.path.join(okf_dir, "2608.00002.md")
        with open(paper2_path, "w", encoding="utf-8") as f:
            f.write(
                "# Paper 2\nSide-channel cryptanalysis and fault attack mitigation."
            )

        aggregator = AnalyticsAggregator(workspace_dir=tmp_dir)
        metrics = aggregator.aggregate_all()

        assert "token_cost_savings_usd" in metrics
        assert "top_threat_vectors" in metrics
        assert "latency_p95_ms" in metrics
        assert "pipeline_slo_pct" in metrics
        assert len(metrics["top_threat_vectors"]) >= 1


def test_analytics_cli_commands() -> None:
    """Verifies Analytics CLI execution."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        res = cli_main(["aggregate", "--workspace-dir", tmp_dir])
        assert res == 0

        res_show = cli_main(["show", "--workspace-dir", tmp_dir])
        assert res_show == 0
