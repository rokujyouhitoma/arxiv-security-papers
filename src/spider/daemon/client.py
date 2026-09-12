#!/usr/bin/env python3
"""
Transparent client interface for dispatching crawl jobs to resident Spider Daemons.
Provides transparent fallback to direct in-process execution when daemons are unavailable.
"""

from __future__ import annotations

import asyncio
import logging
import queue
import time
from typing import Any, Callable, Dict, List, Optional

from .contracts import CrawlJob, CrawlResult

logger = logging.getLogger(__name__)


def _now() -> float:
    return time.time()


def _format_item_entry(item: Any) -> Dict[str, Any]:
    if hasattr(item, "to_dict") and callable(item.to_dict):
        return dict(item.to_dict())
    if isinstance(item, dict):
        return dict(item)
    return {"value": str(item)}


class SpiderDaemonClient:
    """
    Client for interacting with resident Spider Daemons.
    Dispatches via IPC queues when present, with automatic zero-downtime
    fallback to direct synchronous execution.
    """

    def __init__(
        self,
        request_queue: Optional[Any] = None,
        response_queue: Optional[Any] = None,
        fallback_executor: Optional[Callable[[CrawlJob], CrawlResult]] = None,
    ) -> None:
        self.request_queue = request_queue
        self.response_queue = response_queue
        self._fallback_executor = fallback_executor

    def is_daemon_available(self) -> bool:
        """Checks if a valid IPC queue pair is connected."""
        return self.request_queue is not None and self.response_queue is not None

    def _convert_items(self, raw_items: List[Any]) -> List[Dict[str, Any]]:
        return [_format_item_entry(item) for item in raw_items]

    async def _execute_local_async(self, job: CrawlJob) -> CrawlResult:
        start_t = _now()
        params = dict(job.params)
        from ..runner import run_spider

        try:
            raw_items = await run_spider(
                spider_name=job.spider_name,
                output_dir=params.get("output_dir"),
                max_requests=params.get("max_requests"),
                default_delay=float(params.get("default_delay", 0.5)),
                persist_db=bool(params.get("persist_db", False)),
            )
            converted = self._convert_items(raw_items)
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=len(converted),
                items=converted,
                stats={"mode": "fallback_local", "spider": job.spider_name},
                duration_seconds=_now() - start_t,
            )
        except Exception as exc:
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=False,
                error=str(exc),
                duration_seconds=_now() - start_t,
            )

    def _execute_fallback(self, job: CrawlJob) -> CrawlResult:
        if callable(self._fallback_executor):
            return self._fallback_executor(job)
        return asyncio.run(self._execute_local_async(job))

    def _dispatch_via_queue(self, job: CrawlJob, timeout: float) -> CrawlResult:
        if self.request_queue is None or self.response_queue is None:
            raise RuntimeError("IPC queues are not initialized")
        self.request_queue.put(job.to_dict())
        response_data = self.response_queue.get(timeout=timeout)
        if isinstance(response_data, dict):
            return CrawlResult.from_dict(response_data)
        if isinstance(response_data, CrawlResult):
            return response_data
        raise ValueError(f"Invalid response payload type: {type(response_data)}")

    def submit_job(self, job: CrawlJob, timeout: float = 300.0) -> CrawlResult:
        """
        Submits CrawlJob to daemon, seamlessly falling back to local run on failure.
        """
        if not self.is_daemon_available():
            return self._execute_fallback(job)
        try:
            return self._dispatch_via_queue(job, timeout)
        except (queue.Empty, TimeoutError):
            logger.warning(
                "[SpiderClient] IPC timeout after %ss, falling back to local", timeout
            )
            return self._execute_fallback(job)
        except Exception as exc:
            logger.warning("[SpiderClient] IPC error: %s, falling back to local", exc)
            return self._execute_fallback(job)
