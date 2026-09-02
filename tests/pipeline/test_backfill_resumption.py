#!/usr/bin/env python3
"""
Unit and Integration Tests for Autonomous Backfill Resumption and Adaptive Rate Limiter.
Validates state checkpoint persistence, crash recovery, rate limit backoff, and idempotent resumption.
"""

import os
import time
from unittest.mock import MagicMock, patch

import pytest

from pipeline.arxiv_okf_fetcher import run_backfill_pipeline
from pipeline.ingestion.backfill import AdaptiveRateLimiter, BackfillStateManager


def test_adaptive_rate_limiter_basic_and_backoff() -> None:
    limiter = AdaptiveRateLimiter(
        min_interval_sec=0.05,
        initial_backoff_sec=0.1,
        max_backoff_sec=0.4,
    )

    t0 = time.time()
    limiter.wait()
    t1 = time.time()
    assert t1 - t0 >= 0.0

    # Trigger rate limit
    backoff1 = limiter.handle_rate_limit()
    assert backoff1 == 0.1

    # Exponential increase
    backoff2 = limiter.handle_rate_limit()
    assert backoff2 == 0.2

    # Max backoff clamp
    limiter.handle_rate_limit()  # 0.4
    backoff4 = limiter.handle_rate_limit()
    assert backoff4 == 0.4

    # Reset on success
    limiter.handle_success()
    assert limiter._current_backoff == 0.0


def test_backfill_state_manager_lifecycle(tmp_path: pytest.TempPathFactory) -> None:
    state_file = str(tmp_path / "outputs" / "backfill_state.json")
    mgr = BackfillStateManager(state_file=state_file)

    assert mgr.status == "running"
    assert mgr.target_days == 160
    assert len(mgr.completed_dates) == 0

    # Save state
    mgr.save()
    assert os.path.exists(state_file)

    # Mark date completed
    mgr.mark_date_completed("2026-08-30", papers_count=5)
    assert "2026-08-30" in mgr.completed_dates
    assert mgr.total_papers_fetched == 5

    # Reload from disk
    mgr2 = BackfillStateManager(state_file=state_file)
    assert "2026-08-30" in mgr2.completed_dates
    assert mgr2.total_papers_fetched == 5


def test_backfill_state_manager_pending_dates(tmp_path: pytest.TempPathFactory) -> None:
    state_file = str(tmp_path / "backfill_state.json")
    mgr = BackfillStateManager(state_file=state_file)

    pending = mgr.get_pending_dates(days=5)
    assert len(pending) == 5

    # Mark 2 dates completed
    mgr.mark_date_completed(pending[0], papers_count=3)
    mgr.mark_date_completed(pending[1], papers_count=4)

    pending_after = mgr.get_pending_dates(days=5)
    assert len(pending_after) == 3
    assert pending[0] not in pending_after
    assert pending[1] not in pending_after


@patch("pipeline.arxiv_okf_fetcher.run_theme_pipeline")
def test_run_backfill_pipeline_resumption(
    mock_run_theme: MagicMock, tmp_path: pytest.TempPathFactory
) -> None:
    workspace_dir = str(tmp_path)
    state_file = str(tmp_path / "outputs" / "backfill_state.json")

    mock_run_theme.return_value = [{"arxiv_id": "2608.12345", "title": "Test Paper"}]

    # 1. First run for 3 days
    total_fetched = run_backfill_pipeline(
        days=3,
        workspace_dir=workspace_dir,
        checkpoint_file=state_file,
        resume=False,
        theme_id="security",
    )
    assert total_fetched == 3
    assert mock_run_theme.call_count == 3

    # State file should show 3 completed dates
    mgr = BackfillStateManager(state_file=state_file)
    assert len(mgr.completed_dates) == 3
    assert mgr.status == "completed"

    # 2. Resuming when already completed should process 0 additional dates
    mock_run_theme.reset_mock()
    total_resumed = run_backfill_pipeline(
        days=3,
        workspace_dir=workspace_dir,
        checkpoint_file=state_file,
        resume=True,
        theme_id="security",
    )
    assert total_resumed == 0
    assert mock_run_theme.call_count == 0
