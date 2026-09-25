#!/usr/bin/env python3
"""
Unit and integration tests for resident Spider Daemon subsystem.
Tests CrawlJob serialization, HSM session transitions, Politeness retention,
ETag cache persistence, and SpiderDaemonClient fallback execution.
"""

from __future__ import annotations

import datetime
import os
import queue
import shutil
import tempfile
import time
import unittest
from typing import Any, Dict
from unittest.mock import AsyncMock, patch

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.contracts import CrawlJob, CrawlResult, SpiderSessionState
from spider.daemon.worker import SpiderDaemonWorker


class TestSpiderDaemonContracts(unittest.TestCase):
    """Tests data transfer objects and session state mappings."""

    def test_crawl_job_serialization(self) -> None:
        job = CrawlJob(
            spider_name="arxiv",
            params={"max_requests": 5, "output_dir": "outputs/test"},
            priority=10,
        )
        data = job.to_dict()
        self.assertEqual(data["spider_name"], "arxiv")
        self.assertEqual(data["params"]["max_requests"], 5)
        self.assertEqual(data["priority"], 10)

        restored = CrawlJob.from_dict(data)
        self.assertEqual(restored.job_id, job.job_id)
        self.assertEqual(restored.spider_name, "arxiv")
        self.assertEqual(restored.params, job.params)

    def test_crawl_result_serialization(self) -> None:
        result = CrawlResult(
            job_id="job-123",
            spider_name="iacr",
            success=True,
            item_count=2,
            items=[{"title": "Paper A"}, {"title": "Paper B"}],
            stats={"duration": 1.2},
            duration_seconds=1.2,
        )
        data = result.to_dict()
        self.assertTrue(data["success"])
        self.assertEqual(data["item_count"], 2)

        restored = CrawlResult.from_dict(data)
        self.assertEqual(restored.job_id, "job-123")
        self.assertTrue(restored.success)
        self.assertEqual(len(restored.items), 2)

    def test_session_state_properties(self) -> None:
        self.assertEqual(SpiderSessionState.IDLE.super_state, "OPERATIONAL")
        self.assertEqual(SpiderSessionState.FETCHING.super_state, "OPERATIONAL")
        self.assertEqual(SpiderSessionState.BACKOFF.super_state, "OPERATIONAL")
        self.assertEqual(SpiderSessionState.DRAINING.super_state, "TRANSITIONING")
        self.assertEqual(SpiderSessionState.STOPPED.super_state, "TERMINATED")
        self.assertIn("IDLE", SpiderSessionState.IDLE.hierarchical_path)


class TestSpiderDaemonWorker(unittest.TestCase):
    """Tests SpiderDaemonWorker lifecycle, Politeness, and execution."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp()
        self.cache_file = os.path.join(self.temp_dir, "cache.json")
        self.test_db = os.path.join(self.temp_dir, "test_spider.vdb")
        self.worker = SpiderDaemonWorker(
            worker_id="test_worker",
            cache_state_file=self.cache_file,
            db_path=self.test_db,
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_initial_state_and_politeness(self) -> None:
        self.assertEqual(self.worker.current_state, "IDLE")
        self.assertIn("OPERATIONAL.ACTIVE.IDLE", self.worker.current_path)

        now = time.time()
        self.worker.update_politeness("arxiv.org", now)
        self.assertEqual(self.worker.get_last_access("arxiv.org"), now)
        self.assertEqual(self.worker.get_last_access("unknown.org"), 0.0)

    @patch("spider.daemon.worker.run_spider", new_callable=AsyncMock)
    def test_execute_job_sync_success(self, mock_run: AsyncMock) -> None:
        mock_run.return_value = [{"title": "Test Security Paper", "id": "2401.0001"}]
        job = CrawlJob(spider_name="arxiv", params={"max_requests": 1})
        result = self.worker.execute_job_sync(job)

        self.assertTrue(result.success)
        self.assertEqual(result.item_count, 1)
        self.assertEqual(self.worker.jobs_executed, 1)
        self.assertEqual(self.worker.current_state, "IDLE")

    @patch("spider.daemon.worker.run_spider", new_callable=AsyncMock)
    def test_execute_job_sync_rate_limit(self, mock_run: AsyncMock) -> None:
        mock_run.side_effect = RuntimeError("HTTP 429 Too Many Requests")
        job = CrawlJob(spider_name="arxiv")
        result = self.worker.execute_job_sync(job)

        self.assertFalse(result.success)
        self.assertIn("429", str(result.error))
        self.assertEqual(self.worker.current_state, "BACKOFF")

        self.worker.recover_from_backoff()
        self.assertEqual(self.worker.current_state, "IDLE")

    def test_graceful_drain(self) -> None:
        self.worker.drain()
        self.assertEqual(self.worker.current_state, "STOPPED")
        self.assertTrue(os.path.exists(self.cache_file))


class TestSpiderDaemonClient(unittest.TestCase):
    """Tests SpiderDaemonClient queue dispatching and fallback."""

    def test_fallback_when_daemon_unavailable(self) -> None:
        def dummy_fallback(job: CrawlJob) -> CrawlResult:
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=5,
                stats={"source": "custom_fallback"},
            )

        client = SpiderDaemonClient(fallback_executor=dummy_fallback)
        self.assertFalse(client.is_daemon_available())

        job = CrawlJob(spider_name="cwe")
        result = client.submit_job(job)
        self.assertTrue(result.success)
        self.assertEqual(result.item_count, 5)
        self.assertEqual(result.stats.get("source"), "custom_fallback")

    def test_queue_dispatch_success(self) -> None:
        req_q: queue.Queue[Dict[str, Any]] = queue.Queue()
        res_q: queue.Queue[Dict[str, Any]] = queue.Queue()
        client = SpiderDaemonClient(request_queue=req_q, response_queue=res_q)
        self.assertTrue(client.is_daemon_available())

        job = CrawlJob(spider_name="arxiv", job_id="q-job-1")

        # Simulate daemon response
        expected_result = CrawlResult(
            job_id="q-job-1",
            spider_name="arxiv",
            success=True,
            item_count=10,
        )
        res_q.put(expected_result.to_dict())

        result = client.submit_job(job, timeout=1.0)
        self.assertEqual(result.job_id, "q-job-1")
        self.assertTrue(result.success)
        self.assertEqual(result.item_count, 10)

        queued_req = req_q.get_nowait()
        self.assertEqual(queued_req["job_id"], "q-job-1")


class TestSpiderExecutionStorageLock(unittest.TestCase):
    """Tests database-row-based mutual exclusion locking for spider executions."""

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_spider_lock.vdb")
        from spider.daemon.storage import SpiderExecutionStorage

        self.storage = SpiderExecutionStorage(db_path=self.db_path)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_database_row_mutual_exclusion(self) -> None:
        spider = "arxiv"
        # 1. No running job initially
        self.assertFalse(self.storage.has_running_job(spider))
        self.assertIsNone(self.storage.get_running_job(spider))

        # 2. Record start: database row inserted with status = 'RUNNING'
        job = CrawlJob(job_id="lock_test_job_1", spider_name=spider)
        self.storage.record_start(job)

        # 3. Database row exists with status = 'RUNNING' -> lock is active
        self.assertTrue(self.storage.has_running_job(spider))
        running_row = self.storage.get_running_job(spider)
        self.assertIsNotNone(running_row)
        if running_row:
            self.assertEqual(running_row["job_id"], "lock_test_job_1")
            self.assertEqual(running_row["status"], "RUNNING")

        # 4. Record finish: status transitions to 'SUCCESS', finished_at is set
        result = CrawlResult(
            job_id="lock_test_job_1",
            spider_name=spider,
            success=True,
            item_count=10,
        )
        self.storage.record_finish(result)

        # 5. Database row no longer has status = 'RUNNING' -> lock is released
        self.assertFalse(self.storage.has_running_job(spider))
        self.assertIsNone(self.storage.get_running_job(spider))


class TestSpiderStaleJobReconciliation(unittest.TestCase):
    """Tests stale / orphan job detection and automatic reconciliation (Reconciler / Janitor)."""

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test_stale_reconcile.vdb")
        from spider.daemon.storage import SpiderExecutionStorage

        self.storage = SpiderExecutionStorage(db_path=self.db_path)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_reconcile_no_running_jobs(self) -> None:
        self.assertEqual(self.storage.reconcile_stale_jobs(), 0)

    def test_reconcile_recent_running_job_not_interrupted(self) -> None:
        job = CrawlJob(job_id="recent_job_1", spider_name="arxiv")
        self.storage.record_start(job)
        self.assertEqual(self.storage.reconcile_stale_jobs(timeout_seconds=7200.0), 0)
        self.assertTrue(self.storage.has_running_job("arxiv"))

    def _insert_stale_job(
        self, job_id: str, spider_name: str, seconds_ago: float
    ) -> None:
        stale_time = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(
            seconds=seconds_ago
        )
        stale_iso = stale_time.isoformat()
        with self.storage._get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                f"""
                REPLACE INTO spider_execution_logs
                ({self.storage.ALL_COLUMNS_SQL})
                VALUES (?, ?, 'RUNNING', ?, NULL, 0.0, 0, '{{}}', NULL, '{{}}')
                """,
                (job_id, spider_name, stale_iso),
            )
            conn.commit()

    def test_reconcile_stale_running_job_interrupted(self) -> None:
        self._insert_stale_job("stale_job_1", "nvd_cve", 10000.0)
        self.assertTrue(
            self.storage.has_running_job("nvd_cve", max_age_seconds=12000.0)
        )

        reconciled = self.storage.reconcile_stale_jobs(timeout_seconds=7200.0)
        self.assertEqual(reconciled, 1)

        self.assertFalse(self.storage.has_running_job("nvd_cve"))
        history = self.storage.list_history(spider_name="nvd_cve")
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["status"], "INTERRUPTED")
        self.assertIsNotNone(history[0]["finished_at"])
        self.assertIn("timed out or process aborted", str(history[0]["error_message"]))
        self.assertGreaterEqual(float(history[0]["duration_seconds"]), 10000.0)

    def test_workflow_service_startup_reconciles_stale_jobs(self) -> None:
        from workflow.service import WorkflowService

        self._insert_stale_job("startup_stale_1", "cwe", 9000.0)
        service = WorkflowService(storage=self.storage, run_on_startup=False)
        self.assertIsNotNone(service)

        history = self.storage.list_history(spider_name="cwe")
        self.assertEqual(history[0]["status"], "INTERRUPTED")

    @patch("workflow.service.WorkflowService.poll_and_dispatch")
    def test_workflow_lifecycle_hook_on_flush_reconciliation(
        self, mock_dispatch: Any
    ) -> None:
        from workflow.service import WorkflowLifecycleHook

        self._insert_stale_job("watchdog_stale_1", "arxiv", 8000.0)
        hook = WorkflowLifecycleHook(storage=self.storage)
        hook.setup()
        hook._last_reconcile_time = time.time() - 301.0
        hook.on_flush()

        history = self.storage.list_history(spider_name="arxiv")
        self.assertEqual(history[0]["status"], "INTERRUPTED")
        mock_dispatch.assert_called_once()


if __name__ == "__main__":
    unittest.main()
