"""Pause and Resume State Storage for Crawl Frontier and Bloom Filter."""

from __future__ import annotations

import json
import os
from typing import Any, Dict, List

from ..core.downloader import Request
from ..core.scheduler import Scheduler


class StateStorage:
    """Persists and restores Scheduler state (Frontier & Bloom filter) to atomic JSON."""

    @staticmethod
    def save_state(scheduler: Scheduler, filepath: str) -> None:
        """Atomically dumps scheduler frontier and visited URLs to JSON."""
        dir_name = os.path.dirname(filepath)
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)

        pending_requests: List[Dict[str, Any]] = []
        for neg_prio, cnt, req in scheduler._heap:
            pending_requests.append(
                {
                    "url": req.url,
                    "callback": req.callback,
                    "method": req.method,
                    "headers": req.headers,
                    "priority": req.priority,
                    "dont_filter": req.dont_filter,
                    "meta": req.meta,
                }
            )

        state = {
            "version": "1.0",
            "pending_count": len(pending_requests),
            "pending_requests": pending_requests,
            "bloom_count": len(scheduler.bloom),
        }

        temp_path = f"{filepath}.tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
        os.replace(temp_path, filepath)

    @staticmethod
    def restore_state(scheduler: Scheduler, filepath: str) -> int:
        """Restores pending requests into the scheduler from state file."""
        if not os.path.exists(filepath):
            return 0

        with open(filepath, "r", encoding="utf-8") as f:
            state = json.load(f)

        restored = 0
        for item in state.get("pending_requests", []):
            req = Request(
                url=item["url"],
                callback=item.get("callback", "parse"),
                method=item.get("method", "GET"),
                headers=item.get("headers", {}),
                priority=item.get("priority", 0),
                dont_filter=item.get("dont_filter", False),
                meta=item.get("meta", {}),
            )
            if scheduler.enqueue(req):
                restored += 1

        return restored
