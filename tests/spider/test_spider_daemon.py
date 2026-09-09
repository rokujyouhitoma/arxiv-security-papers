#!/usr/bin/env python3
"""
Unit and integration tests for resident Spider Daemon subsystem.
Tests CrawlJob serialization, HSM session transitions, Politeness retention,
ETag cache persistence, and SpiderDaemonClient fallback execution.
"""

from __future__ import annotations

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
        self.worker = SpiderDaemonWorker(
            worker_id="test_worker",
            cache_state_file=self.cache_file,
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


if __name__ == "__main__":
    unittest.main()
