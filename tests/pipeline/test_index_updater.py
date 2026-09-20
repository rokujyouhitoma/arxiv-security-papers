"""
Unit tests for Index & Log Updater (Portal layout and decoupling).
"""

import os
import tempfile
from typing import Any, Dict

from pipeline.reporter.index_updater import (
    MAX_INDEX_PAPERS,
    _build_index_rows,
    update_index_and_log,
)


def _create_mock_okf_paper(day_dir: str, paper_id: str, title: str) -> None:
    os.makedirs(day_dir, exist_ok=True)
    file_path = os.path.join(day_dir, f"{paper_id}.md")
    content = f"""---
type: "security-paper"
title: "{title}"
title_ja: "{title}（日本語訳）"
description: "テスト要約文"
resource: "https://arxiv.org/abs/{paper_id}"
---
# {title}
"""
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)


def test_index_updater_portal_structure() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        config: Dict[str, Any] = {
            "paths": {
                "okf_papers_dir": "outputs/okf_papers",
                "raw_data_dir": "outputs/raw_data",
                "index_file": "outputs/index.md",
                "log_file": "outputs/log.md",
            }
        }

        # Create 3 mock papers
        day_dir = os.path.join(tmpdir, "outputs", "okf_papers", "2026-09-20")
        _create_mock_okf_paper(day_dir, "2609.00001", "Security Test Paper 1")
        _create_mock_okf_paper(day_dir, "2609.00002", "Security Test Paper 2")

        update_index_and_log(
            tmpdir,
            new_items=[{"id": "2609.00001"}, {"id": "2609.00002"}],
            per_run_path=os.path.join(
                tmpdir, "outputs/executive_summaries/01_per_run/run_1200.md"
            ),
            daily_path=os.path.join(
                tmpdir, "outputs/executive_summaries/02_daily/2026-09-20.md"
            ),
            monthly_path=os.path.join(
                tmpdir, "outputs/executive_summaries/03_monthly/monthly.md"
            ),
            quarterly_path=os.path.join(
                tmpdir, "outputs/executive_summaries/04_quarterly/quarterly.md"
            ),
            annual_path=os.path.join(
                tmpdir, "outputs/executive_summaries/05_annual/annual.md"
            ),
            config=config,
            limit=50,
        )

        index_file = os.path.join(tmpdir, "outputs", "index.md")
        assert os.path.exists(index_file)

        with open(index_file, "r", encoding="utf-8") as f:
            content = f.read()

        # Check Portal components
        assert "全件検索・データアクセス基盤 (Decoupled Catalog Views)" in content
        assert "[Web Console](../site/index.html)" in content
        assert "[papers_catalog.json](database/papers_catalog.json)" in content
        assert "ソート済みエグゼクティブサマリー層 (日本語サマリー)" in content
        assert "直近登録論文ハイライト (最新 50 件)" in content
        assert "Security Test Paper 1" in content
        assert "Security Test Paper 2" in content
        assert "全論文の検索・閲覧について" in content


def test_build_index_rows_limit() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        config: Dict[str, Any] = {
            "paths": {
                "okf_papers_dir": "outputs/okf_papers",
                "raw_data_dir": "outputs/raw_data",
            }
        }
        index_dir = os.path.join(tmpdir, "outputs")

        # Create 60 mock papers across 2 days (30 per day)
        day1 = os.path.join(tmpdir, "outputs", "okf_papers", "2026-09-19")
        day2 = os.path.join(tmpdir, "outputs", "okf_papers", "2026-09-20")

        for i in range(1, 31):
            _create_mock_okf_paper(day1, f"2609.190{i:02d}", f"Paper 19-{i}")
            _create_mock_okf_paper(day2, f"2609.200{i:02d}", f"Paper 20-{i}")

        # Default limit = 50
        assert MAX_INDEX_PAPERS == 50
        rows_default = _build_index_rows(tmpdir, config, index_dir, limit=50)
        assert len(rows_default) == 50

        # Most recent day (2026-09-20) should be first 30 rows
        assert "2609.20001" in rows_default[0]
        # Next 20 rows should come from 2026-09-19
        assert "2026-09-19" in rows_default[30]

        # Custom limit = 10
        rows_10 = _build_index_rows(tmpdir, config, index_dir, limit=10)
        assert len(rows_10) == 10

        # No limit (all 60)
        rows_all = _build_index_rows(tmpdir, config, index_dir, limit=None)
        assert len(rows_all) == 60
