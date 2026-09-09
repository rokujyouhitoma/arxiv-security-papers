#!/usr/bin/env python3
"""
Spider Daemon package.
Exports resident crawler components: CrawlJob, CrawlResult, SpiderDaemonWorker, and SpiderDaemonClient.
"""

from .client import SpiderDaemonClient
from .contracts import (
    CrawlJob,
    CrawlResult,
    SpiderSessionState,
    build_spider_session_state_tree,
)
from .worker import SpiderDaemonWorker

__all__ = [
    "CrawlJob",
    "CrawlResult",
    "SpiderSessionState",
    "SpiderDaemonWorker",
    "SpiderDaemonClient",
    "build_spider_session_state_tree",
]
