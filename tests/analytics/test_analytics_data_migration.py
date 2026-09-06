#!/usr/bin/env python3
"""
Unit tests for Analytics time-series & snapshot data migration.
Verifies zero-data-loss portable migration between storage backends powered by src/database.
"""

import os
import tempfile
from typing import Generator

import pytest

from analytics.storage import AnalyticsStorage


@pytest.fixture
def temp_analytics_db_paths() -> Generator[tuple[str, str], None, None]:
    with tempfile.TemporaryDirectory() as tmpdir:
        src_path = os.path.join(tmpdir, "source_analytics.db")
        dst_path = os.path.join(tmpdir, "dest_analytics.db")
        yield src_path, dst_path


def test_analytics_data_export_and_import_migration(
    temp_analytics_db_paths: tuple[str, str],
) -> None:
    src_path, dst_path = temp_analytics_db_paths

    # 1. Initialize source and save a snapshot
    src_storage = AnalyticsStorage(
        analytics_dir=os.path.dirname(src_path),
        db_name=os.path.basename(src_path),
    )
    test_metrics = {
        "top_threat_vectors": [
            {
                "name": "Ransomware Operations",
                "category": "Malware",
                "count": 42,
                "prev_count": 30,
                "growth_pct": 40.0,
                "sample_ids": "2408.12345",
            }
        ],
        "kpis": {
            "token_reduction_pct": 78.5,
            "pipeline_sla_compliance": 99.9,
        },
        "system_kpis": {
            "total_papers": 1250,
        },
    }
    src_storage.save_snapshot(test_metrics)

    # Verify latest snapshot can be loaded
    latest = src_storage.load_latest_metrics()
    assert latest is not None
    assert latest["kpis"]["token_reduction_pct"] == 78.5

    # 2. Export dataset into portable structured dictionary
    dataset = src_storage.export_analytics_dataset()
    assert "threat_trends" in dataset
    assert "strategic_kpis" in dataset
    assert "metrics_history" in dataset
    assert "latest_snapshot" in dataset
    assert len(dataset["threat_trends"]) == 1
    assert dataset["threat_trends"][0]["name"] == "Ransomware Operations"
    assert len(dataset["latest_snapshot"]) == 1

    # 3. Import dataset into clean destination storage
    dst_storage = AnalyticsStorage(
        analytics_dir=os.path.dirname(dst_path),
        db_name=os.path.basename(dst_path),
    )
    restored_count = dst_storage.import_analytics_dataset(dataset)
    assert restored_count >= 3

    # 4. Verify data integrity and snapshot loading from restored destination
    dst_latest = dst_storage.load_latest_metrics()
    assert dst_latest is not None
    assert dst_latest["kpis"]["token_reduction_pct"] == 78.5
    assert dst_latest["top_threat_vectors"][0]["name"] == "Ransomware Operations"
