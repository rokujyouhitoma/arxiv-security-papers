#!/usr/bin/env python3
"""
Unit and integration tests for SpiderWorker under the Process Supervisor.
Tests job polling, heartbeat reporting, max_requests retirement, and graceful drain.
"""

from __future__ import annotations

import queue
import shutil
import tempfile
import unittest
from typing import Any, Dict, Optional
from unittest.mock import MagicMock, patch

from spider.daemon.contracts import CrawlJob
from supervisor.config import SupervisorConfig
from supervisor.contracts import DefaultLifecycleHook, ServiceRole, WorkerSpec
from supervisor.workers.spider_worker import SpiderWorker


class TestSpiderWorker(unittest.TestCase):
    """Tests SpiderWorker supervisor integration."""

    def setUp(self) -> None:
        self.config = SupervisorConfig()
        self.source_q: queue.Queue[Dict[str, Any]] = queue.Queue()
        self.result_q: queue.Queue[Dict[str, Any]] = queue.Queue()
        self.temp_dir = tempfile.mkdtemp()
        self.pulses: list[Dict[str, Any]] = []

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _record_pulse(self, pid: int, meta: Optional[Dict[str, Any]]) -> None:
        if meta is not None:
            self.pulses.append(meta)

    def test_spider_worker_initialization(self) -> None:
        worker = SpiderWorker(
            worker_id="spider_01",
            config=self.config,
            source_queue=self.source_q,
            result_queue=self.result_q,
            cache_state_file=f"{self.temp_dir}/cache.json",
            pulse_callback=self._record_pulse,
            max_requests=10,
        )
        self.assertEqual(worker.worker_id, "spider_01")
        self.assertEqual(worker.max_requests, 10)
        self.assertEqual(worker.requests_handled, 0)
        self.assertTrue(worker.alive)

    @patch("spider.daemon.worker.run_spider")
    def test_process_single_job(self, mock_run: MagicMock) -> None:
        async def dummy_run(*args: Any, **kwargs: Any) -> list[Dict[str, Any]]:
            return [{"id": "paper_1"}]

        mock_run.side_effect = dummy_run
        worker = SpiderWorker(
            worker_id="spider_01",
            config=self.config,
            source_queue=self.source_q,
            result_queue=self.result_q,
            cache_state_file=f"{self.temp_dir}/cache.json",
            pulse_callback=self._record_pulse,
        )

        job = CrawlJob(spider_name="arxiv", job_id="job-abc")
        worker._process_single_job(job)

        self.assertEqual(worker.requests_handled, 1)
        self.assertFalse(self.result_q.empty())
        res = self.result_q.get_nowait()
        self.assertEqual(res["job_id"], "job-abc")
        self.assertTrue(res["success"])

        # Check pulse recorded state_path
        self.assertTrue(any(p.get("handling") is True for p in self.pulses))
        self.assertTrue(
            any("OPERATIONAL" in str(p.get("state_path")) for p in self.pulses)
        )

    def test_worker_retirement(self) -> None:
        worker = SpiderWorker(
            worker_id="spider_retire",
            config=self.config,
            source_queue=self.source_q,
            max_requests=1,
        )
        worker.requests_handled = 1
        self.assertTrue(worker._should_retire())

    def test_shutdown_and_hook(self) -> None:
        teardown_mock = MagicMock()
        hook = DefaultLifecycleHook(teardown_fn=teardown_mock)

        worker = SpiderWorker(
            worker_id="spider_drain",
            config=self.config,
            hook=hook,
            cache_state_file=f"{self.temp_dir}/drain_cache.json",
        )
        worker._shutdown_worker()
        teardown_mock.assert_called_once()
        self.assertEqual(worker.daemon.current_state, "STOPPED")

    def test_worker_spec_spider_class(self) -> None:
        spec = WorkerSpec(
            name="spider_pool",
            worker_class="spider",
            target_count=2,
            role=ServiceRole.STATELESS_POOL,
        )
        self.assertEqual(spec.worker_class, "spider")
        self.assertEqual(spec.target_count, 2)


if __name__ == "__main__":
    unittest.main()
