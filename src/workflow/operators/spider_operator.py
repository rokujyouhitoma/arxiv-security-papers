#!/usr/bin/env python3
"""
SpiderTaskOperator for Universal Workflow Engine.
Binds DAG tasks to resident SpiderDaemonWorker via SpiderDaemonClient,
with automatic fallback to synchronous execution.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.contracts import CrawlJob, CrawlResult

logger = logging.getLogger(__name__)


def _copy_context_key(
    merged: Dict[str, Any], context: Dict[str, Any], key: str
) -> None:
    if key in context and key not in merged:
        merged[key] = context[key]


def _merge_params(
    base_params: Optional[Dict[str, Any]], context: Dict[str, Any]
) -> Dict[str, Any]:
    merged: Dict[str, Any] = dict(base_params or {})
    ctx_params = context.get("spider_params")
    if isinstance(ctx_params, dict):
        merged.update(ctx_params)
    for key in ("output_dir", "max_requests", "default_delay", "persist_db"):
        _copy_context_key(merged, context, key)
    return merged


class SpiderTaskOperator:
    """
    Workflow Task Operator executing web scraping tasks.
    Can be directly passed as a TaskNode handler in DAGWorkflowEngine.
    """

    def __init__(
        self,
        spider_name: str,
        client: Optional[SpiderDaemonClient] = None,
        params: Optional[Dict[str, Any]] = None,
        timeout: float = 300.0,
        output_key: str = "crawl_result",
    ) -> None:
        self.spider_name = spider_name
        self.client = client if client is not None else SpiderDaemonClient()
        self.params = dict(params or {})
        self.timeout = timeout
        self.output_key = output_key

    def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Executes crawl job via SpiderDaemonClient and updates context dict."""
        merged_params = _merge_params(self.params, context)
        job = CrawlJob(
            spider_name=self.spider_name,
            params=merged_params,
        )
        result: CrawlResult = self.client.submit_job(job, timeout=self.timeout)
        return {
            self.output_key: result.to_dict(),
            f"{self.spider_name}_items_count": result.item_count,
            f"{self.spider_name}_success": result.success,
        }

    def __call__(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Enables direct invocation as a DAG node handler."""
        return self.execute(context)
