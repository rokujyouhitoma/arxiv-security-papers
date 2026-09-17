#!/usr/bin/env python3
"""
Unit tests for Spider execution database persistence and Web Gateway APIs.
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from typing import Any, List
from unittest.mock import MagicMock, patch

from spider.daemon.contracts import CrawlJob, CrawlResult
from spider.daemon.storage import SpiderExecutionStorage
from web.gateway.handlers import GatewayHandlers
from workflow.service import WorkflowLifecycleHook


class TestSpiderExecutionStorage(unittest.TestCase):
    """Verifies SQLite persistence for spider execution logs."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "spider_test.db")
        self.storage = SpiderExecutionStorage(db_path=self.db_path)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_record_start_and_finish_success(self) -> None:
        job = CrawlJob(job_id="test_job_1", spider_name="arxiv", params={"limit": 10})
        self.storage.record_start(job)

        history = self.storage.list_history(spider_name="arxiv")
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["job_id"], "test_job_1")
        self.assertEqual(history[0]["status"], "RUNNING")

        result = CrawlResult(
            job_id="test_job_1",
            spider_name="arxiv",
            success=True,
            item_count=5,
            duration_seconds=1.23,
            stats={"http_200": 5},
        )
        self.storage.record_finish(result)

        updated = self.storage.list_history(spider_name="arxiv")
        self.assertEqual(len(updated), 1)
        self.assertEqual(updated[0]["status"], "SUCCESS")
        self.assertEqual(updated[0]["item_count"], 5)
        self.assertEqual(updated[0]["duration_seconds"], 1.23)

    def test_get_status_summary(self) -> None:
        job1 = CrawlJob(job_id="j1", spider_name="arxiv")
        self.storage.record_start(job1)
        self.storage.record_finish(
            CrawlResult(
                job_id="j1",
                spider_name="arxiv",
                success=True,
                item_count=10,
                duration_seconds=2.0,
            )
        )

        job2 = CrawlJob(job_id="j2", spider_name="cwe")
        self.storage.record_start(job2)
        self.storage.record_finish(
            CrawlResult(
                job_id="j2",
                spider_name="cwe",
                success=False,
                error="Connection timeout",
            )
        )

        summary = self.storage.get_status_summary()
        self.assertIn("arxiv", summary)
        self.assertIn("cwe", summary)
        self.assertEqual(summary["arxiv"]["status"], "SUCCESS")
        self.assertEqual(summary["arxiv"]["item_count"], 10)
        self.assertEqual(summary["cwe"]["status"], "FAILED")


class TestWorkflowService(unittest.TestCase):
    """Verifies workflow scheduler dispatching."""

    @patch("spider.daemon.client.SpiderDaemonClient.submit_job")
    def test_task_scheduling_logic(self, mock_submit: MagicMock) -> None:
        mock_submit.return_value = CrawlResult(
            job_id="test", spider_name="arxiv", success=True
        )
        hook = WorkflowLifecycleHook()
        self.assertTrue(hook.setup())
        self.assertTrue(hook.health_check())

        metrics = hook.get_metrics()
        self.assertEqual(metrics["tasks_count"], 3)

        hook.on_flush()
        # Ensure submit_job was called for registered tasks
        self.assertGreaterEqual(mock_submit.call_count, 1)

        hook.teardown()
        self.assertFalse(hook.health_check())


class TestWebGatewaySpiderApis(unittest.TestCase):
    """Verifies Web Gateway spider status, history, and trigger endpoints."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        db_dir = os.path.join(self.temp_dir.name, "outputs", "database")
        os.makedirs(db_dir, exist_ok=True)
        self.handlers = GatewayHandlers(workspace_dir=self.temp_dir.name)
        # Pre-populate DB
        db_path = os.path.join(db_dir, "spider_execution.db")
        storage = SpiderExecutionStorage(db_path=db_path)
        job = CrawlJob(job_id="api_test_job", spider_name="arxiv")
        storage.record_start(job)
        storage.record_finish(
            CrawlResult(
                job_id="api_test_job",
                spider_name="arxiv",
                success=True,
                item_count=42,
                duration_seconds=0.5,
            )
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_spider_status_endpoint(self) -> None:
        status_received = []

        def mock_start_response(status: str, headers: List[Any]) -> None:
            status_received.append(status)

        res_bytes = self.handlers.handle_spider_status(mock_start_response)
        data = json.loads(b"".join(res_bytes).decode("utf-8"))
        self.assertEqual(status_received[0], "200 OK")
        self.assertEqual(data["status"], "ok")
        self.assertIn("arxiv", data["spiders"])
        self.assertEqual(data["spiders"]["arxiv"]["item_count"], 42)

    def test_spider_history_endpoint(self) -> None:
        status_received = []

        def mock_start_response(status: str, headers: List[Any]) -> None:
            status_received.append(status)

        res_bytes = self.handlers.handle_spider_history(
            mock_start_response, {"spider_name": ["arxiv"], "limit": ["10"]}
        )
        data = json.loads(b"".join(res_bytes).decode("utf-8"))
        self.assertEqual(status_received[0], "200 OK")
        self.assertEqual(len(data["history"]), 1)
        self.assertEqual(data["history"][0]["job_id"], "api_test_job")

    @patch("threading.Thread")
    def test_spider_trigger_endpoint(self, mock_thread_cls: MagicMock) -> None:
        status_received = []

        def mock_start_response(status: str, headers: List[Any]) -> None:
            status_received.append(status)

        import io

        environ = {
            "REQUEST_METHOD": "POST",
            "CONTENT_LENGTH": "25",
            "wsgi.input": io.BytesIO(b'{"spider_name": "cwe"}'),
        }
        res_bytes = self.handlers.handle_spider_trigger(environ, mock_start_response)
        data = json.loads(b"".join(res_bytes).decode("utf-8"))
        self.assertEqual(status_received[0], "200 OK")
        self.assertEqual(data["status"], "ok")
        self.assertIn("cwe", data["message"])
        self.assertTrue(mock_thread_cls.return_value.start.called)


if __name__ == "__main__":
    unittest.main()
