#!/usr/bin/env python3
"""
SpiderWorker process implementation for the Process Supervisor.
Runs a resident SpiderDaemonWorker, dequeues CrawlJobs, and reports heartbeats to Arbiter.
"""

from __future__ import annotations

import logging
import queue
import time
from typing import Any, Callable, Dict, Optional

from spider.daemon.contracts import CrawlJob, CrawlResult
from spider.daemon.worker import SpiderDaemonWorker

from ..config import SupervisorConfig
from ..contracts import LifecycleHook
from .base import BaseWorker

logger = logging.getLogger(__name__)


def _now() -> float:
    return time.time()


class SpiderWorker(BaseWorker):
    """
    Supervisor-managed resident crawler worker.
    Processes CrawlJobs with heartbeat reporting, graceful drain, and automatic retirement.
    """

    def __init__(
        self,
        worker_id: str,
        config: SupervisorConfig,
        server_socket: Optional[Any] = None,
        app_target: Optional[Callable[[Any], Any]] = None,
        source_queue: Optional[Any] = None,
        result_queue: Optional[Any] = None,
        cache_state_file: Optional[str] = "outputs/spider/cache_state.json",
        hook: Optional[LifecycleHook] = None,
        poll_interval: float = 0.1,
        pulse_callback: Optional[
            Callable[[int, Optional[Dict[str, Any]]], None]
        ] = None,
        max_requests: int = 0,
        max_requests_jitter: int = 0,
        max_worker_lifetime: float = 0.0,
        max_worker_lifetime_jitter: float = 0.0,
    ) -> None:
        super().__init__(
            worker_id=worker_id,
            config=config,
            server_socket=server_socket,
            app_target=app_target,
            pulse_callback=pulse_callback,
            max_requests=max_requests,
            max_requests_jitter=max_requests_jitter,
            max_worker_lifetime=max_worker_lifetime,
            max_worker_lifetime_jitter=max_worker_lifetime_jitter,
        )
        self.source_queue = source_queue
        self.result_queue = result_queue
        self.hook = hook
        self.poll_interval = max(0.01, poll_interval)
        self.daemon = SpiderDaemonWorker(
            worker_id=worker_id, cache_state_file=cache_state_file
        )

    def _fetch_job(self) -> Optional[CrawlJob]:
        if self.source_queue is None:
            return None
        try:
            item = self.source_queue.get(timeout=self.poll_interval)
            if isinstance(item, CrawlJob):
                return item
            if isinstance(item, dict):
                return CrawlJob.from_dict(item)
            return None
        except (queue.Empty, Exception):
            return None

    def _send_result(self, result: CrawlResult) -> None:
        if self.result_queue is not None:
            try:
                self.result_queue.put(result.to_dict())
            except Exception as exc:
                logger.error(
                    "[SpiderWorker %s] Error enqueueing result: %s", self.worker_id, exc
                )

    def _process_single_job(self, job: CrawlJob) -> None:
        self.pulse(
            {
                "handling": True,
                "job_id": job.job_id,
                "state_path": self.daemon.current_path,
            }
        )
        result = self.daemon.execute_job_sync(job)
        self._send_result(result)
        self.requests_handled += 1
        if self._should_retire():
            self.alive = False

    def _execute_hook_setup(self) -> bool:
        if self.hook is not None:
            self.hook.bind_worker(self.worker_id)
            return bool(self.hook.setup())
        return True

    def _execute_hook_teardown(self) -> None:
        if self.hook is not None:
            self.hook.teardown()

    def _handle_idle_tick(self) -> None:
        self.pulse({"handling": False, "state_path": self.daemon.current_path})
        time.sleep(self.poll_interval)

    def run(self) -> None:
        """Main resident consumer execution loop."""
        if not self._execute_hook_setup():
            logger.error(
                "[SpiderWorker %s] LifecycleHook.setup() failed", self.worker_id
            )
            return

        while self.alive:
            job = self._fetch_job()
            if job is not None:
                self._process_single_job(job)
            else:
                self._handle_idle_tick()

        self._shutdown_worker()

    def _shutdown_worker(self) -> None:
        logger.info("[SpiderWorker %s] Initiating graceful drain", self.worker_id)
        self.daemon.drain()
        self._execute_hook_teardown()
        logger.info("[SpiderWorker %s] Worker shutdown complete", self.worker_id)
