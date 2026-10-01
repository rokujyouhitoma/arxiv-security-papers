#!/usr/bin/env python3
"""
Full-Stages End-to-End (E2E) Integration Test Suite for the Intelligence Pipeline.
Validates Stage 1 (Ingestion) -> Stage 2 (Transformation) -> Stage 3 (Reporting),
idempotency, catalog consistency, 5-tier summaries, and SSE event emissions.
"""

from __future__ import annotations

import os
import tempfile
from typing import Any, List
from unittest.mock import patch

from pipeline.arxiv_okf_fetcher import run_theme_pipeline
from pipeline.events import PipelineEventBroadcaster
from pipeline.ingestion.adapters.base import RawItem


def test_pipeline_full_stages_e2e_execution_and_idempotency() -> None:
    broadcaster = PipelineEventBroadcaster.get_instance()
    broadcaster.reset()
    event_queue = broadcaster.subscribe()

    sample_raw_items: List[RawItem] = [
        RawItem(
            item_id="2608.99001v1",
            clean_id="2608.99001",
            title="Adversarial Prompt Injections against Multimodal LLMs",
            abstract="We present threat vectors and mitigation strategies for multimodal agents.",
            authors=["Alice Smith", "Bob Jones"],
            published="2026-08-20T10:00:00Z",
            updated="2026-08-20T10:00:00Z",
            url="https://arxiv.org/abs/2608.99001",
            source_type="arxiv",
            categories=["cs.CR", "cs.AI"],
        ),
        RawItem(
            item_id="2608.99002v1",
            clean_id="2608.99002",
            title="Formally Verifying Post-Quantum Key Encapsulation Mechanisms",
            abstract="Formal verification of Kyber lattice implementations against side channels.",
            authors=["Charlie Brown"],
            published="2026-08-20T11:00:00Z",
            updated="2026-08-20T11:00:00Z",
            url="https://arxiv.org/abs/2608.99002",
            source_type="arxiv",
            categories=["cs.CR"],
        ),
    ]

    def mock_fetch_theme(
        theme: Any, max_res: Any, s_dt: Any, e_dt: Any
    ) -> List[RawItem]:
        return sample_raw_items

    def mock_download_pdf(paper: dict[str, Any], path: str) -> None:
        with open(path, "wb") as f:
            f.write(b"%PDF-1.4 dummy content")

    def mock_extract_text(pdf_path: str, txt_path: str) -> None:
        with open(txt_path, "w", encoding="utf-8") as f:
            f.write(
                "Extracted text regarding cybersecurity vulnerability and verification."
            )

    with tempfile.TemporaryDirectory() as tmp_workspace:
        # Patch only external network I/O; run real pipeline transformation and reporting!
        with patch(
            "pipeline.arxiv_okf_fetcher._fetch_theme_raw_items",
            side_effect=mock_fetch_theme,
        ):
            with patch(
                "pipeline.ingestion.pdf_extractor._download_pdf_file",
                side_effect=mock_download_pdf,
            ):
                with patch(
                    "pipeline.ingestion.pdf_extractor._extract_text_with_fallback",
                    side_effect=mock_extract_text,
                ):
                    # ---------------------------------------------------------
                    # 1. First Execution: Process 2 new papers through all 3 stages
                    # ---------------------------------------------------------
                    processed = run_theme_pipeline(
                        theme_id="security",
                        workspace_dir=tmp_workspace,
                        max_results=5,
                        force=False,
                    )

                    assert len(processed) == 2

                    # --- Stage 1 Verification (Raw Data) ---
                    raw_day_dir = os.path.join(
                        tmp_workspace, "outputs", "raw_data", "2026-08-20"
                    )
                    assert os.path.exists(raw_day_dir)
                    assert os.path.exists(
                        os.path.join(raw_day_dir, "2608.99001_meta.json")
                    )
                    assert os.path.exists(os.path.join(raw_day_dir, "2608.99001.pdf"))
                    assert os.path.exists(os.path.join(raw_day_dir, "2608.99001.txt"))
                    assert os.path.exists(
                        os.path.join(raw_day_dir, "2608.99002_meta.json")
                    )

                    # --- Stage 2 Verification (Google OKF v0.2 Markdown) ---
                    okf_day_dir = os.path.join(
                        tmp_workspace, "outputs", "okf", "papers", "2026-08-20"
                    )
                    okf_file1 = os.path.join(okf_day_dir, "2608.99001.md")
                    okf_file2 = os.path.join(okf_day_dir, "2608.99002.md")
                    assert os.path.exists(okf_file1)
                    assert os.path.exists(okf_file2)

                    with open(okf_file1, "r", encoding="utf-8") as f:
                        okf_text = f.read()
                    assert 'type: "security-paper"' in okf_text
                    assert "https://arxiv.org/abs/2608.99001" in okf_text
                    assert "エグゼクティブサマリー" in okf_text

                    # --- Stage 3 Verification (5-Tier Summaries & Catalog) ---
                    cat_path = os.path.join(
                        tmp_workspace, "outputs", "database", "papers_catalog.json"
                    )
                    assert os.path.exists(cat_path)

                    log_path = os.path.join(tmp_workspace, "outputs", "log.md")
                    assert os.path.exists(log_path)

                    exec_dir = os.path.join(
                        tmp_workspace, "outputs", "executive_summaries"
                    )
                    per_run_dir = os.path.join(exec_dir, "01_per_run")
                    daily_dir = os.path.join(exec_dir, "02_daily")
                    monthly_dir = os.path.join(exec_dir, "03_monthly")
                    quarterly_dir = os.path.join(exec_dir, "04_quarterly")
                    annual_dir = os.path.join(exec_dir, "05_annual")

                    assert os.path.exists(per_run_dir)
                    assert os.path.exists(daily_dir)
                    assert os.path.exists(monthly_dir)
                    assert os.path.exists(quarterly_dir)
                    assert os.path.exists(annual_dir)

                    daily_file = os.path.join(daily_dir, "2026-08-20.md")
                    assert os.path.exists(daily_file)
                    with open(daily_file, "r", encoding="utf-8") as f:
                        daily_md = f.read()
                    assert "2608.99001" in daily_md
                    assert "2608.99002" in daily_md

                    # --- Event Broadcaster Verification ---
                    events = []
                    while not event_queue.empty():
                        events.append(event_queue.get_nowait())

                    event_types = [e["type"] for e in events]
                    assert "pipeline_start" in event_types
                    assert "stage_start" in event_types
                    assert "ingestion_progress" in event_types
                    assert "transformation_progress" in event_types
                    assert "pipeline_finish" in event_types

                    # ---------------------------------------------------------
                    # 2. Second Execution: Idempotency check (no duplicate run)
                    # ---------------------------------------------------------
                    processed_again = run_theme_pipeline(
                        theme_id="security",
                        workspace_dir=tmp_workspace,
                        max_results=5,
                        force=False,
                    )
                    assert len(processed_again) == 0

    broadcaster.reset()
