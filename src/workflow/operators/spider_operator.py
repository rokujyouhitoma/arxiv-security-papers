#!/usr/bin/env python3
"""
SpiderTaskOperator for Universal Workflow Engine.
Binds DAG tasks to resident SpiderDaemonWorker via SpiderDaemonClient,
with automatic fallback to synchronous execution.
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, Optional

from spider.daemon.client import SpiderDaemonClient
from spider.daemon.contracts import CrawlJob, CrawlResult
from spider.daemon.storage import SpiderExecutionStorage

logger = logging.getLogger(__name__)


def _normalize_spider_name(name: str) -> str:
    mapping = {
        "kev_cve": "cisa_kev",
        "cve": "nvd_cve",
        "cve_nvd": "nvd_cve",
    }
    return mapping.get(name, name)


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
    if "persist_db" not in merged:
        merged["persist_db"] = True
    return merged


def _handle_execution_error(
    storage: SpiderExecutionStorage,
    job: CrawlJob,
    exc: Exception,
    start_t: float,
) -> None:
    logger.exception(
        "[SpiderTaskOperator] Job '%s' (%s) execution error: %s",
        job.job_id,
        job.spider_name,
        exc,
    )
    failed_res = CrawlResult(
        job_id=job.job_id,
        spider_name=job.spider_name,
        success=False,
        error=str(exc),
        duration_seconds=time.time() - start_t,
    )
    storage.record_finish(failed_res)


def _resolve_storage(
    storage: Optional[SpiderExecutionStorage],
    db_path: Optional[str],
) -> SpiderExecutionStorage:
    if storage is not None:
        return storage
    return SpiderExecutionStorage(db_path=db_path)


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
        storage: Optional[SpiderExecutionStorage] = None,
        db_path: Optional[str] = None,
    ) -> None:
        self.spider_name = _normalize_spider_name(spider_name)
        self.client = client if client is not None else SpiderDaemonClient()
        self.params = dict(params or {})
        self.timeout = timeout
        self.output_key = output_key
        self.storage = _resolve_storage(storage, db_path)

    def execute(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Executes crawl job via SpiderDaemonClient and updates context dict."""
        merged_params = _merge_params(self.params, context)
        job_id = f"scheduled_{self.spider_name}_{int(time.time())}"
        job = CrawlJob(
            job_id=job_id,
            spider_name=self.spider_name,
            params=merged_params,
        )
        start_t = time.time()
        self.storage.record_start(job)
        try:
            result: CrawlResult = self.client.submit_job(job, timeout=self.timeout)
            self.storage.record_finish(result)
        except Exception as exc:
            _handle_execution_error(self.storage, job, exc, start_t)
            raise

        return {
            self.output_key: result.to_dict(),
            f"{self.spider_name}_items_count": result.item_count,
            f"{self.spider_name}_success": result.success,
        }

    def __call__(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Enables direct invocation as a DAG node handler."""
        return self.execute(context)
