#!/usr/bin/env python3
"""
Resident Spider Daemon Worker engine.
Provides persistent HTTP connection management, Politeness retention,
ETag cache sharing, and DSN-23 HSM session lifecycle governance.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import Any, Dict, List, Optional

from core.hsm import HierarchicalStateMachine

from .contracts import CrawlJob, CrawlResult, build_spider_session_state_tree

logger = logging.getLogger(__name__)


def _now() -> float:
    return time.time()


def _ensure_dir(path: str) -> None:
    dirname = os.path.dirname(path)
    if dirname:
        os.makedirs(dirname, exist_ok=True)


class SpiderDaemonWorker:
    """
    Resident worker engine that maintains persistent crawler state across multiple CrawlJobs.
    Governed by a 3-tier Hierarchical State Machine (HSM).
    """

    def __init__(
        self,
        worker_id: str = "daemon_01",
        cache_state_file: Optional[str] = "outputs/spider/cache_state.json",
    ) -> None:
        self.worker_id = worker_id
        self.cache_state_file = cache_state_file
        self.state_tree = build_spider_session_state_tree(worker_id)
        self.hsm = HierarchicalStateMachine(
            root=self.state_tree,
            fail_secure_target="TERMINATED.FAILED",
        )
        self._politeness_table: Dict[str, float] = {}
        self._cache_store: Dict[str, Dict[str, Any]] = {}
        self.jobs_executed: int = 0
        self._load_cache_from_disk()
        self._complete_setup()

    def _complete_setup(self) -> None:
        self.hsm.send_event("SETUP_SUCCESS")

    @property
    def current_state(self) -> str:
        """Returns the leaf state name."""
        return self.hsm.current_state.name

    @property
    def current_path(self) -> str:
        """Returns the full hierarchical dotted state path."""
        return self.hsm.current_state.get_path()

    def _load_cache_from_disk(self) -> None:
        if not self.cache_state_file or not os.path.exists(self.cache_state_file):
            return
        try:
            with open(self.cache_state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                self._cache_store = data
        except Exception as exc:
            logger.warning(
                "[SpiderWorker %s] Failed loading cache: %s", self.worker_id, exc
            )

    def _persist_cache_to_disk(self) -> None:
        if not self.cache_state_file:
            return
        try:
            _ensure_dir(self.cache_state_file)
            with open(self.cache_state_file, "w", encoding="utf-8") as f:
                json.dump(self._cache_store, f)
        except Exception as exc:
            logger.warning(
                "[SpiderWorker %s] Failed saving cache: %s", self.worker_id, exc
            )

    def update_politeness(
        self, domain: str, access_time: Optional[float] = None
    ) -> None:
        """Records last access time for a domain to respect politeness rules."""
        self._politeness_table[domain] = (
            access_time if access_time is not None else _now()
        )

    def get_last_access(self, domain: str) -> float:
        """Returns the last recorded access timestamp for domain."""
        return self._politeness_table.get(domain, 0.0)

    def _format_item_entry(self, item: Any) -> Dict[str, Any]:
        if hasattr(item, "to_dict") and callable(item.to_dict):
            return dict(item.to_dict())
        if isinstance(item, dict):
            return dict(item)
        return {"value": str(item)}

    def _convert_items(self, items: List[Any]) -> List[Dict[str, Any]]:
        return [self._format_item_entry(item) for item in items]

    async def _execute_crawl(self, job: CrawlJob) -> tuple[List[Any], Dict[str, Any]]:
        params = dict(job.params)
        output_dir = params.get("output_dir")
        max_requests = params.get("max_requests")
        default_delay = float(params.get("default_delay", 0.5))
        persist_db = bool(params.get("persist_db", False))
        from ..runner import run_spider

        raw_items = await run_spider(
            spider_name=job.spider_name,
            output_dir=output_dir,
            max_requests=max_requests,
            default_delay=default_delay,
            persist_db=persist_db,
        )
        stats: Dict[str, Any] = {
            "spider": job.spider_name,
            "items_count": len(raw_items),
            "executed_by": self.worker_id,
        }
        return raw_items, stats

    def _handle_job_error(
        self, job: CrawlJob, exc: Exception, start_t: float
    ) -> CrawlResult:
        err_msg = str(exc)
        logger.error(
            "[SpiderWorker %s] Job %s failed: %s", self.worker_id, job.job_id, exc
        )
        if "429" in err_msg or "rate limit" in err_msg.lower():
            self.hsm.send_event("RATE_LIMIT")
        else:
            self.hsm.send_event("JOB_DONE")
        return CrawlResult(
            job_id=job.job_id,
            spider_name=job.spider_name,
            success=False,
            error=err_msg,
            duration_seconds=_now() - start_t,
        )

    def _handle_job_success(
        self,
        job: CrawlJob,
        raw_items: List[Any],
        stats: Dict[str, Any],
        start_t: float,
    ) -> CrawlResult:
        converted = self._convert_items(raw_items)
        self.jobs_executed += 1
        self.hsm.send_event("JOB_DONE")
        return CrawlResult(
            job_id=job.job_id,
            spider_name=job.spider_name,
            success=True,
            item_count=len(converted),
            items=converted,
            stats=stats,
            duration_seconds=_now() - start_t,
        )

    async def execute_job(self, job: CrawlJob) -> CrawlResult:
        """
        Executes a crawl job under HSM state transitions.
        IDLE -> FETCHING -> IDLE (or BACKOFF).
        """
        start_t = _now()
        self.hsm.send_event("START_JOB")
        try:
            raw_items, stats = await self._execute_crawl(job)
            return self._handle_job_success(job, raw_items, stats, start_t)
        except Exception as exc:
            return self._handle_job_error(job, exc, start_t)

    def execute_job_sync(self, job: CrawlJob) -> CrawlResult:
        """Synchronous wrapper for execute_job."""
        return asyncio.run(self.execute_job(job))

    def recover_from_backoff(self) -> None:
        """Transitions from BACKOFF back to IDLE after cooldown expires."""
        if self.current_state == "BACKOFF":
            self.hsm.send_event("COOLDOWN_DONE")

    def drain(self) -> None:
        """
        Initiates graceful session drain: flushes ETag cache and closes connections.
        OPERATIONAL -> TRANSITIONING.DRAINING -> TERMINATED.STOPPED.
        """
        self.hsm.send_event("SIGQUIT")
        self._persist_cache_to_disk()
        self.hsm.send_event("DRAIN_COMPLETE")
