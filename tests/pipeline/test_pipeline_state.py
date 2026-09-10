#!/usr/bin/env python3
"""
Unit tests for PipelineStateManager.
Tests O(1) paper deduplication, execution audit trail, log.md projection,
and legacy migration from processed_papers.json.
Pure Python, zero external dependencies.
"""

import json
import os
import tempfile
from typing import Any, Dict

from pipeline.pipeline_state import PipelineStateManager


def test_pipeline_state_dedup_and_clean_id() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        manager = PipelineStateManager(db_dir=tmp_dir)

        assert not manager.is_paper_processed("2608.13465v1")
        assert not manager.is_paper_processed("2608_13465")

        paper = {
            "arxiv_id": "2608.13465v1",
            "title": "Malware Concept Drift Detection",
            "published": "2026-08-13T16:46:56Z",
        }
        manager.register_paper(paper)

        # Both raw arxiv_id and clean_id must be recognized
        assert manager.is_paper_processed("2608.13465v1")
        assert manager.is_paper_processed("2608_13465")
        assert not manager.is_paper_processed("2608.99999v1")


def test_pipeline_state_run_events_and_recent() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        manager = PipelineStateManager(db_dir=tmp_dir)

        assert manager.get_recent_runs() == []

        manager.record_run_start("run_001", category="cs.CR")
        manager.record_run_complete(
            run_id="run_001",
            status="SUCCESS",
            fetched=15,
            processed=15,
            duration_sec=4.2,
            details="All OKF converted",
        )

        manager.record_run_start("run_002", category="cs.CR")
        manager.record_run_complete(
            run_id="run_002",
            status="PARTIAL",
            fetched=5,
            processed=4,
            duration_sec=2.1,
            details="1 PDF extraction failed",
        )

        recent = manager.get_recent_runs()
        assert len(recent) == 2
        # Reverse chronological
        assert recent[0]["run_id"] == "run_002"
        assert recent[0]["status"] == "PARTIAL"
        assert recent[1]["run_id"] == "run_001"
        assert recent[1]["status"] == "SUCCESS"


def test_pipeline_state_project_log_markdown() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        manager = PipelineStateManager(db_dir=tmp_dir)
        log_file = os.path.join(tmp_dir, "log.md")

        manager.record_run_complete(
            run_id="run_20260911_000537",
            status="SUCCESS",
            fetched=12,
            processed=12,
            duration_sec=3.5,
            details="Batch completed",
        )

        manager.project_log_markdown(output_path=log_file, limit=10)

        assert os.path.exists(log_file)
        with open(log_file, "r", encoding="utf-8") as f:
            content = f.read()

        assert "# パイプライン実行ログ台帳 (Pipeline Run Ledger)" in content
        assert "run_20260911_000537" in content
        assert "**SUCCESS**" in content
        assert "3.5s" in content
        assert "Batch completed" in content


def test_pipeline_state_legacy_migration() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        legacy_file = os.path.join(tmp_dir, "legacy_processed.json")
        sample_data: Dict[str, Any] = {
            "2608.11111v1": {
                "title": "Legacy Paper 1",
                "processed_at": "2026-08-14T00:00:00Z",
            },
            "2608.22222v2": {
                "title": "Legacy Paper 2",
                "processed_at": "2026-08-14T01:00:00Z",
            },
        }
        with open(legacy_file, "w", encoding="utf-8") as f:
            json.dump(sample_data, f)

        manager = PipelineStateManager(db_dir=os.path.join(tmp_dir, "db"))
        migrated = manager.migrate_legacy_processed_papers(legacy_file)

        assert migrated == 2
        assert manager.is_paper_processed("2608.11111v1")
        assert manager.is_paper_processed("2608_11111")
        assert manager.is_paper_processed("2608.22222v2")
        assert manager.is_paper_processed("2608_22222")

        # Second migration must be no-op (catalog already populated)
        assert manager.migrate_legacy_processed_papers(legacy_file) == 0
