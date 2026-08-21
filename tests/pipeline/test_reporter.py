"""
Unit tests for the Reporter layer (5-tier summaries, Mermaid mindmaps, index & log updates).
"""

import os
import tempfile

from pipeline.reporter import (
    generate_all_daily_summaries,
    generate_annual_summary,
    generate_mermaid_mindmap,
    generate_monthly_summary,
    generate_per_run_summary,
    generate_quarterly_summary,
    update_index_and_log,
)


def test_generate_mermaid_mindmap():
    papers = [
        {"primary_category": "cs.CR"},
        {"primary_category": "cs.CR"},
        {"primary_category": "cs.AI"},
    ]
    mermaid = generate_mermaid_mindmap(papers)
    assert "```mermaid" in mermaid
    assert "mindmap" in mermaid
    assert "cs.CR (2 papers)" in mermaid
    assert "cs.AI (1 papers)" in mermaid


def test_reporter_5_tier_summaries_and_index():
    with tempfile.TemporaryDirectory() as tmpdir:
        config = {
            "paths": {
                "okf_papers_dir": "outputs/okf_papers",
                "per_run_dir": "outputs/executive_summaries/01_per_run",
                "daily_dir": "outputs/executive_summaries/02_daily",
                "monthly_dir": "outputs/executive_summaries/03_monthly",
                "quarterly_dir": "outputs/executive_summaries/04_quarterly",
                "annual_dir": "outputs/executive_summaries/05_annual",
                "index_file": "outputs/index.md",
                "log_file": "outputs/log.md",
                "raw_data_dir": "outputs/raw_data",
                "templates_dir": "templates",
            }
        }

        # Create sample OKF paper
        day_dir = os.path.join(tmpdir, "outputs/okf_papers/2026-08-17")
        os.makedirs(day_dir, exist_ok=True)
        okf_path = os.path.join(day_dir, "2608.55555.md")

        with open(okf_path, "w", encoding="utf-8") as f:
            f.write("""---
type: "security-paper"
title: "Agentic Penetration Testing Security"
title_ja: "エージェント型ペネトレーションテストのセキュリティ"
description: "自律型エージェントの検証"
published_date: "2026-08-17"
---
# Agentic Penetration Testing Security
arXiv ID = [`2608.55555v1`]
""")

        processed_item = {
            "paper": {
                "arxiv_id": "2608.55555v1",
                "title": "Agentic Penetration Testing Security",
                "abs_url": "https://arxiv.org/abs/2608.55555",
            },
            "okf_path": okf_path,
            "rel_okf_path": "outputs/okf_papers/2026-08-17/2608.55555.md",
            "exec_summary": {
                "one_liner": "エージェント型ペネトレーションテストの検証",
            },
            "title_ja": "エージェント型ペネトレーションテストのセキュリティ",
            "date_str": "2026-08-17",
        }

        # 1. 01_per_run
        pr_path = generate_per_run_summary([processed_item], tmpdir, config)
        assert os.path.exists(pr_path)
        with open(pr_path, "r", encoding="utf-8") as f:
            assert "01_per_run" in f.read()

        # 2. 02_daily
        d_path = generate_all_daily_summaries(tmpdir, config)
        assert os.path.exists(d_path)

        # 3. 03_monthly
        m_path = generate_monthly_summary(tmpdir, config)
        assert os.path.exists(m_path)

        # 4. 04_quarterly
        q_path = generate_quarterly_summary(tmpdir, config)
        assert os.path.exists(q_path)

        # 5. 05_annual
        a_path = generate_annual_summary(tmpdir, config)
        assert os.path.exists(a_path)

        # 6. Index & Log
        update_index_and_log(
            tmpdir, [processed_item], pr_path, d_path, m_path, q_path, a_path, config
        )
        index_file = os.path.join(tmpdir, "outputs/index.md")
        log_file = os.path.join(tmpdir, "outputs/log.md")
        assert os.path.exists(index_file)
        assert os.path.exists(log_file)
