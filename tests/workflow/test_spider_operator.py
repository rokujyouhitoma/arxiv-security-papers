#!/usr/bin/env python3
"""
Unit and integration tests for SpiderTaskOperator in Universal Workflow Engine.
Tests DAG integration, parameter passing, and client dispatch.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from typing import Any, Dict

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.contracts import CrawlJob, CrawlResult
from spider.daemon.storage import SpiderExecutionStorage
from workflow.dag import DAGWorkflowEngine
from workflow.operators.spider_operator import SpiderTaskOperator


class TestSpiderTaskOperator(unittest.TestCase):
    """Tests SpiderTaskOperator execution within workflow DAGs."""

    def test_direct_operator_execution(self) -> None:
        def dummy_fallback(job: CrawlJob) -> CrawlResult:
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=3,
                items=[{"id": 1}, {"id": 2}, {"id": 3}],
                stats={"max": job.params.get("max_requests")},
            )

        client = SpiderDaemonClient(fallback_executor=dummy_fallback)
        operator = SpiderTaskOperator(
            spider_name="arxiv",
            client=client,
            params={"max_requests": 5},
            output_key="arxiv_data",
        )

        initial_context = {"pipeline_id": "dag-001"}
        result = operator(initial_context)

        self.assertIn("arxiv_data", result)
        self.assertEqual(result["arxiv_items_count"], 3)
        self.assertTrue(result["arxiv_success"])
        self.assertEqual(result["arxiv_data"]["stats"]["max"], 5)

    def test_dag_workflow_integration(self) -> None:
        def dummy_fallback(job: CrawlJob) -> CrawlResult:
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=1,
                items=[{"url": f"https://example.com/{job.spider_name}"}],
            )

        client = SpiderDaemonClient(fallback_executor=dummy_fallback)
        dag = DAGWorkflowEngine()

        # Step 1: Config node
        def config_handler(ctx: Dict[str, Any]) -> Dict[str, Any]:
            return {"target_domain": "arxiv.org", "max_requests": 10}

        # Step 2: Spider node
        spider_op = SpiderTaskOperator(
            spider_name="arxiv",
            client=client,
            output_key="crawled_papers",
        )

        # Step 3: Analysis node
        def analyze_handler(ctx: Dict[str, Any]) -> Dict[str, Any]:
            count = ctx.get("arxiv_items_count", 0)
            return {"analysis_report": f"Processed {count} items"}

        dag.add_node("config", config_handler)
        dag.add_node("crawl", spider_op, dependencies=["config"])
        dag.add_node("analyze", analyze_handler, dependencies=["crawl"])

        final_state = dag.execute()

        self.assertEqual(final_state["target_domain"], "arxiv.org")
        self.assertEqual(final_state["arxiv_items_count"], 1)
        self.assertIn("crawled_papers", final_state)
        self.assertEqual(final_state["analysis_report"], "Processed 1 items")

    def test_workflow_scheduler_with_spider_task(self) -> None:
        from workflow.scheduler import WorkflowScheduler

        def dummy_fallback(job: CrawlJob) -> CrawlResult:
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=2,
            )

        client = SpiderDaemonClient(fallback_executor=dummy_fallback)
        scheduler = WorkflowScheduler()
        task = scheduler.register_spider_task(
            spider_name="cwe",
            interval_seconds=0.01,
            client=client,
        )

        self.assertEqual(task.metadata["spider_name"], "cwe")
        self.assertTrue(task.is_due())

        executed = scheduler.run_due_tasks()
        self.assertIn(task.task_id, executed)
        self.assertFalse(task.is_due())

    def test_operator_records_start_and_finish_in_storage(self) -> None:
        recorded_jobs = []
        recorded_results = []

        class MockStorage:
            def record_start(self, job: CrawlJob) -> None:
                recorded_jobs.append(job)

            def record_finish(self, result: CrawlResult) -> None:
                recorded_results.append(result)

        captured_job = []

        def dummy_fallback(job: CrawlJob) -> CrawlResult:
            captured_job.append(job)
            return CrawlResult(
                job_id=job.job_id,
                spider_name=job.spider_name,
                success=True,
                item_count=5,
            )

        mock_storage = MockStorage()
        client = SpiderDaemonClient(fallback_executor=dummy_fallback)
        operator = SpiderTaskOperator(
            spider_name="kev_cve",  # Should be normalized to cisa_kev
            client=client,
            storage=mock_storage,  # type: ignore[arg-type]
        )

        result = operator({})

        self.assertEqual(len(recorded_jobs), 1)
        job = recorded_jobs[0]
        self.assertTrue(job.job_id.startswith("scheduled_cisa_kev_"))
        self.assertEqual(job.spider_name, "cisa_kev")
        self.assertTrue(job.params.get("persist_db"))

        self.assertEqual(len(recorded_results), 1)
        res = recorded_results[0]
        self.assertEqual(res.job_id, job.job_id)
        self.assertTrue(res.success)
        self.assertEqual(res.item_count, 5)

        self.assertTrue(result["cisa_kev_success"])
        self.assertEqual(result["cisa_kev_items_count"], 5)

    def test_operator_records_failure_on_exception(self) -> None:
        recorded_jobs = []
        recorded_results = []

        class MockStorage:
            def record_start(self, job: CrawlJob) -> None:
                recorded_jobs.append(job)

            def record_finish(self, result: CrawlResult) -> None:
                recorded_results.append(result)

        def failing_fallback(job: CrawlJob) -> CrawlResult:
            raise RuntimeError("Crawl connection failed")

        mock_storage = MockStorage()
        client = SpiderDaemonClient(fallback_executor=failing_fallback)
        operator = SpiderTaskOperator(
            spider_name="arxiv",
            client=client,
            storage=mock_storage,  # type: ignore[arg-type]
        )

        with self.assertRaises(RuntimeError) as ctx:
            operator({})

        self.assertIn("Crawl connection failed", str(ctx.exception))
        self.assertEqual(len(recorded_jobs), 1)
        self.assertEqual(len(recorded_results), 1)

        failed_res = recorded_results[0]
        self.assertFalse(failed_res.success)
        self.assertIn("Crawl connection failed", failed_res.error or "")
        self.assertTrue(failed_res.job_id.startswith("scheduled_arxiv_"))

    def test_spider_operator_integration_with_live_storage(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            test_db = os.path.join(tmpdir, "test_spider_execution.vdb")
            storage = SpiderExecutionStorage(db_path=test_db)

            def dummy_fallback(job: CrawlJob) -> CrawlResult:
                return CrawlResult(
                    job_id=job.job_id,
                    spider_name=job.spider_name,
                    success=True,
                    item_count=12,
                )

            client = SpiderDaemonClient(fallback_executor=dummy_fallback)
            operator = SpiderTaskOperator(
                spider_name="arxiv",
                client=client,
                storage=storage,
            )

            res = operator({"spider_params": {"max_requests": 20}})
            self.assertTrue(res["arxiv_success"])
            self.assertEqual(res["arxiv_items_count"], 12)

            # Introspect DB
            history = storage.list_history(limit=10)
            self.assertEqual(len(history), 1)
            entry = history[0]
            self.assertTrue(entry["job_id"].startswith("scheduled_arxiv_"))
            self.assertEqual(entry["spider_name"], "arxiv")
            self.assertEqual(entry["status"], "SUCCESS")
            self.assertEqual(entry["item_count"], 12)


if __name__ == "__main__":
    unittest.main()
