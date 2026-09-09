#!/usr/bin/env python3
"""
Unit and integration tests for SpiderTaskOperator in Universal Workflow Engine.
Tests DAG integration, parameter passing, and client dispatch.
"""

from __future__ import annotations

import unittest
from typing import Any, Dict

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.contracts import CrawlJob, CrawlResult
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


if __name__ == "__main__":
    unittest.main()
