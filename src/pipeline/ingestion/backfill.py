#!/usr/bin/env python3
"""
Backfill State Manager & Adaptive Rate Limiter Module.
Provides robust checkpointing for resuming large-scale multi-day arXiv paper fetching,
and ensures strict compliance with rate limiting and exponential backoff policies.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


class AdaptiveRateLimiter:
    """
    Token-bucket style rate limiter with strict minimum request intervals
    and exponential backoff on HTTP 429/503 errors.
    """

    def __init__(
        self,
        min_interval_sec: float = 3.0,
        initial_backoff_sec: float = 8.0,
        max_backoff_sec: float = 64.0,
    ) -> None:
        self.min_interval_sec = min_interval_sec
        self.initial_backoff_sec = initial_backoff_sec
        self.max_backoff_sec = max_backoff_sec
        self._last_request_time: float = 0.0
        self._current_backoff: float = 0.0

    def wait(self) -> float:
        """Enforces minimum interval and active backoff delay before request."""
        now = time.time()
        elapsed = now - self._last_request_time
        needed = self.min_interval_sec + self._current_backoff

        sleep_time = max(0.0, needed - elapsed)
        if sleep_time > 0:
            time.sleep(sleep_time)

        self._last_request_time = time.time()
        return sleep_time

    def handle_success(self) -> None:
        """Resets active backoff delay upon successful request."""
        self._current_backoff = 0.0

    def handle_rate_limit(self) -> float:
        """Increases backoff exponentially on rate limiting (HTTP 429/503)."""
        if self._current_backoff <= 0.0:
            self._current_backoff = self.initial_backoff_sec
        else:
            self._current_backoff = min(
                self._current_backoff * 2.0, self.max_backoff_sec
            )
        logger.warning(
            "arXiv rate limit triggered. Backoff set to %.1fs",
            self._current_backoff,
        )
        return self._current_backoff


class BackfillStateManager:
    """
    Atomic state checkpoint manager for long-running backfill jobs.
    Persists target days, completed dates, and active cursor into backfill_state.json.
    """

    def __init__(self, state_file: str = "outputs/backfill_state.json") -> None:
        self.state_file = state_file
        self.version = "1.0"
        self.target_days = 160
        self.start_time: str = datetime.now(timezone.utc).isoformat()
        self.last_updated: str = self.start_time
        self.current_target_date: Optional[str] = None
        self.current_page: int = 0
        self.completed_dates: Set[str] = set()
        self.total_papers_fetched: int = 0
        self.status: str = "running"
        self.load()

    def load(self) -> bool:
        """Loads state from checkpoint file if it exists."""
        if not os.path.exists(self.state_file):
            return False
        try:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._apply_dict(data)
            return True
        except Exception as e:
            logger.error(
                "Failed to load backfill state from %s: %s", self.state_file, e
            )
            return False

    def _apply_dict(self, data: Dict[str, Any]) -> None:
        """Applies dictionary fields to state attributes."""
        self.version = str(data.get("version", "1.0"))
        self.target_days = int(data.get("target_days", 160))
        self.start_time = str(data.get("start_time", self.start_time))
        self.last_updated = str(data.get("last_updated", self.last_updated))
        self.current_target_date = data.get("current_target_date")
        self.current_page = int(data.get("current_page", 0))
        self.completed_dates = set(data.get("completed_dates", []))
        self.total_papers_fetched = int(data.get("total_papers_fetched", 0))
        self.status = str(data.get("status", "running"))

    def to_dict(self) -> Dict[str, Any]:
        """Serializes state to dictionary."""
        return {
            "version": self.version,
            "target_days": self.target_days,
            "start_time": self.start_time,
            "last_updated": datetime.now(timezone.utc).isoformat(),
            "current_target_date": self.current_target_date,
            "current_page": self.current_page,
            "completed_dates": sorted(list(self.completed_dates)),
            "total_papers_fetched": self.total_papers_fetched,
            "status": self.status,
        }

    def save(self) -> None:
        """Atomically saves checkpoint using temp file replacement."""
        os.makedirs(os.path.dirname(os.path.abspath(self.state_file)), exist_ok=True)
        dir_name = os.path.dirname(os.path.abspath(self.state_file))
        data = self.to_dict()

        with tempfile.NamedTemporaryFile(
            "w", dir=dir_name, delete=False, encoding="utf-8"
        ) as tf:
            json.dump(data, tf, indent=2, ensure_ascii=False)
            temp_path = tf.name

        os.replace(temp_path, self.state_file)

    def mark_date_completed(self, date_str: str, papers_count: int = 0) -> None:
        """Marks a target date as completed and advances counts."""
        self.completed_dates.add(date_str)
        self.total_papers_fetched += papers_count
        self.current_page = 0
        self.save()

    def get_pending_dates(self, days: int) -> List[str]:
        """Calculates sorted list of pending dates going back N days from today."""
        self.target_days = days
        today = datetime.now(timezone.utc).date()
        all_dates = [
            (today - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days)
        ]
        return [d for d in all_dates if d not in self.completed_dates]
