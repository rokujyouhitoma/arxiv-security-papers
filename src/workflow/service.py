#!/usr/bin/env python3
"""
Workflow Service & Supervisor LifecycleHook.
Manages the resident WorkflowScheduler, registers scheduled crawlers,
and dispatches periodic tasks on each supervisor sync tick.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any, Dict, Optional

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.storage import SpiderExecutionStorage
from supervisor.contracts import LifecycleHook

from .scheduler import WorkflowScheduler

logger = logging.getLogger(__name__)


class WorkflowService:
    """Core domain service coordinating the WorkflowScheduler and periodic triggers."""

    def __init__(
        self,
        run_on_startup: Optional[bool] = None,
        storage: Optional[SpiderExecutionStorage] = None,
        db_path: Optional[str] = None,
    ) -> None:
        self.scheduler = WorkflowScheduler()
        self.client = SpiderDaemonClient()
        self.storage = storage
        self.db_path = db_path
        self.tasks_registered = False
        if self.storage is None:
            self._init_default_storage()
        self._reconcile_on_startup()
        if run_on_startup is None:
            self.run_on_startup = os.getenv(
                "ARXIV_SPIDER_RUN_ON_STARTUP", "true"
            ).lower() in ("1", "true", "yes")
        else:
            self.run_on_startup = run_on_startup

    def _init_default_storage(self) -> None:
        try:
            self.storage = SpiderExecutionStorage(db_path=self.db_path)
        except Exception as exc:
            logger.warning("[WorkflowService] Could not init default storage: %s", exc)

    def _reconcile_on_startup(self) -> None:
        if self.storage is None:
            return
        try:
            self.storage.reconcile_stale_jobs()
        except Exception as exc:
            logger.warning(
                "[WorkflowService] Failed to reconcile stale jobs: %s", exc
            )

    def register_default_spider_tasks(
        self, run_on_startup: Optional[bool] = None
    ) -> None:
        """Registers default periodic spider crawlers (arXiv, CWE, CVE)."""
        if self.tasks_registered:
            return
        ros = self.run_on_startup if run_on_startup is None else run_on_startup
        # arXiv: every 6 hours (21600 seconds)
        self.scheduler.register_spider_task(
            spider_name="arxiv",
            interval_seconds=21600.0,
            client=self.client,
            task_id="spider_arxiv_6h",
            run_on_startup=ros,
            storage=self.storage,
            db_path=self.db_path,
        )
        # MITRE CWE: every 24 hours (86400 seconds)
        self.scheduler.register_spider_task(
            spider_name="cwe",
            interval_seconds=86400.0,
            client=self.client,
            task_id="spider_cwe_24h",
            run_on_startup=ros,
            storage=self.storage,
            db_path=self.db_path,
        )
        # CISA KEV & NVD CVE: every 6 hours (21600 seconds)
        self.scheduler.register_spider_task(
            spider_name="cve_nvd",
            interval_seconds=21600.0,
            client=self.client,
            task_id="spider_cve_nvd_6h",
            run_on_startup=ros,
            storage=self.storage,
            db_path=self.db_path,
        )
        self.tasks_registered = True
        logger.info(
            "[WorkflowService] Registered default periodic spider tasks (run_on_startup=%s).",
            ros,
        )

    def poll_and_dispatch(self) -> int:
        """Triggers due tasks in the scheduler."""
        executed = self.scheduler.run_due_tasks()
        return len(executed)


class WorkflowLifecycleHook(LifecycleHook):
    """Supervisor LifecycleHook managing the WorkflowService and periodic crawler scheduler."""

    def __init__(
        self,
        storage: Optional[SpiderExecutionStorage] = None,
        db_path: Optional[str] = None,
    ) -> None:
        self.service: Optional[WorkflowService] = None
        self.worker_id = "workflow_01"
        self.storage = storage
        self.db_path = db_path
        self._last_reconcile_time: float = 0.0

    def bind_worker(self, worker_id: str) -> None:
        self.worker_id = worker_id

    def setup(self) -> bool:
        """Initializes WorkflowService and registers default spider schedules."""
        try:
            self.service = WorkflowService(storage=self.storage, db_path=self.db_path)
            self.service.register_default_spider_tasks()
            return True
        except Exception as exc:
            logger.error(
                "[WorkflowLifecycleHook %s] Setup failed: %s", self.worker_id, exc
            )
            return False

    def health_check(self) -> bool:
        """Health check returns True if the service instance is active."""
        return self.service is not None

    def _safe_reconcile(self, storage: SpiderExecutionStorage) -> None:
        try:
            storage.reconcile_stale_jobs()
        except Exception as exc:
            logger.warning(
                "[WorkflowLifecycleHook %s] Stale reconciliation error: %s",
                self.worker_id,
                exc,
            )

    def _run_storage_reconcile(self) -> None:
        if self.service and self.service.storage:
            self._safe_reconcile(self.service.storage)

    def _maybe_reconcile_stale(self, now: float) -> None:
        if (now - self._last_reconcile_time) >= 300.0:
            self._last_reconcile_time = now
            self._run_storage_reconcile()

    def on_flush(self) -> None:
        """Invoked periodically by ManagedServiceWorker to poll and dispatch due tasks."""
        if self.service is not None:
            try:
                self.service.poll_and_dispatch()
                self._maybe_reconcile_stale(time.time())
            except Exception as exc:
                logger.error(
                    "[WorkflowLifecycleHook %s] Poll error: %s", self.worker_id, exc
                )

    def teardown(self) -> None:
        """Clean teardown releasing resources."""
        self.service = None

    def get_metrics(self) -> Dict[str, Any]:
        """Provides structured telemetry for Supervisor Top."""
        if not self.service:
            return {}
        tasks = self.service.scheduler.list_tasks()
        return {
            "tasks_count": len(tasks),
            "requests_handled": sum(1 for t in tasks if t.get("last_run", 0) > 0),
        }
