"""Spider CLI Runner - User code entrypoint for executing and managing spiders."""

from __future__ import annotations

import argparse
import asyncio
import os
from typing import Any, Dict, List, Optional, Sequence

from .core.downloader import AsyncHttpDownloader
from .core.engine import Engine, ScrapedItem
from .core.scheduler import Scheduler
from .distributed.state_storage import StateStorage
from .downloader.middleware import (
    HttpCacheMiddleware,
    RobotsTxtMiddleware,
    UserAgentMiddleware,
)
from .pipeline.okf_pipeline import OkfItemPipeline
from .policies.autothrottle import AutoThrottlePolicy
from .registry import get_spider_registry
from .spiders.base import BaseSpider


def get_available_spiders() -> Dict[str, type[BaseSpider]]:
    """Retrieves all registered spiders dynamically via SpiderRegistry."""
    registry = get_spider_registry()
    spiders: Dict[str, type[BaseSpider]] = {}
    for name in registry.list_spiders():
        cls = registry.get(name)
        if cls is not None:
            spiders[name] = cls
            # Register short aliases without _spider suffix
            if name.endswith("_spider"):
                short_name = name[: -len("_spider")]
                spiders[short_name] = cls
    return spiders


def _init_scheduler_state(
    scheduler: Scheduler, state_file: Optional[str], resume: bool
) -> None:
    if resume and state_file and os.path.exists(state_file):
        restored = StateStorage.restore_state(scheduler, state_file)
        print(f"[*] Resumed {restored} requests from state: {state_file}")


def _build_spider_middlewares(default_delay: float, enable_cache: bool) -> List[Any]:
    middlewares: List[Any] = [
        UserAgentMiddleware(),
        RobotsTxtMiddleware(),
        AutoThrottlePolicy(min_delay=default_delay),
    ]
    if enable_cache:
        middlewares.append(HttpCacheMiddleware())
    return middlewares


async def run_spider(
    spider_name: str,
    output_dir: str = "outputs/okf_papers",
    max_requests: Optional[int] = None,
    default_delay: float = 0.5,
    enable_cache: bool = True,
    persist_db: bool = False,
    state_file: Optional[str] = None,
    resume_from_state: bool = False,
) -> List[ScrapedItem]:
    """Runs a specific spider with full middleware and pipeline stack."""
    avail = get_available_spiders()
    if spider_name not in avail:
        raise ValueError(
            f"Unknown spider: {spider_name}. Available: {list(avail.keys())}"
        )

    spider_instance = avail[spider_name]()
    scheduler = Scheduler(default_delay=default_delay)
    _init_scheduler_state(scheduler, state_file, resume_from_state)

    downloader = AsyncHttpDownloader()
    engine = Engine(downloader=downloader, scheduler=scheduler)
    middlewares = _build_spider_middlewares(default_delay, enable_cache)
    pipelines = [
        OkfItemPipeline(output_dir=output_dir, enable_db_persistence=persist_db)
    ]

    print(
        f"[*] Starting Spider: '{spider_name}' (start_urls: {len(spider_instance.start_urls)})"
    )
    items = await engine.crawl(
        spider=spider_instance,
        pipelines=pipelines,
        middlewares=middlewares,
        max_requests=max_requests,
    )

    if state_file:
        StateStorage.save_state(scheduler, state_file)
        print(f"[*] Saved scheduler state to: {state_file}")

    print(
        f"[+] Spider '{spider_name}' completed. Scraped {len(items)} items. Stats: {engine.get_stats()}"
    )
    return items


async def run_all_spiders(
    output_dir: str = "outputs/okf_papers",
    max_requests_per_spider: Optional[int] = None,
    persist_db: bool = False,
) -> Dict[str, List[ScrapedItem]]:
    """Runs all registered spiders sequentially."""
    results: Dict[str, List[ScrapedItem]] = {}
    avail = get_available_spiders()
    for name in avail:
        items = await run_spider(
            spider_name=name,
            output_dir=output_dir,
            max_requests=max_requests_per_spider,
            persist_db=persist_db,
        )
        results[name] = items
    return results


class SpiderRunner:
    """Synchronous orchestration wrapper for executing spiders."""

    def __init__(self, workspace_dir: Optional[str] = None) -> None:
        self.workspace_dir = workspace_dir or os.getcwd()
        self.output_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")

    def run_spider(
        self,
        spider_name: str,
        max_depth: Optional[int] = None,
        max_requests: Optional[int] = None,
    ) -> Dict[str, Any]:
        """Runs the spider synchronously and returns stats."""
        items = asyncio.run(
            run_spider(
                spider_name=spider_name,
                output_dir=self.output_dir,
                max_requests=max_requests or max_depth,
            )
        )
        return {"spider": spider_name, "crawled": len(items)}


def parse_cli_args(args: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Large-Scale Distributed Spider & Crawler Runner (DSN-15)"
    )
    avail_names = list(get_available_spiders().keys())
    parser.add_argument(
        "--spider",
        choices=avail_names + ["all"] if avail_names else None,
        default=(
            "arxiv"
            if "arxiv" in avail_names
            else (avail_names[0] if avail_names else None)
        ),
        help="Target spider to run",
    )
    parser.add_argument(
        "--output-dir",
        default="outputs/okf_papers",
        help="Directory for OKF v0.2 Markdown outputs",
    )
    parser.add_argument(
        "--max-requests",
        type=int,
        default=None,
        help="Maximum number of requests to process",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Default politeness crawl delay in seconds",
    )
    parser.add_argument(
        "--persist-db", action="store_true", help="Persist records into DSN-14 Database"
    )
    parser.add_argument(
        "--state-file", default=None, help="Path to state file for Pause/Resume"
    )
    parser.add_argument("--resume", action="store_true", help="Resume from state file")
    return parser.parse_args(args)


def main() -> None:
    args = parse_cli_args()
    if args.spider == "all":
        asyncio.run(
            run_all_spiders(
                output_dir=args.output_dir,
                max_requests_per_spider=args.max_requests,
                persist_db=args.persist_db,
            )
        )
    else:
        asyncio.run(
            run_spider(
                spider_name=args.spider,
                output_dir=args.output_dir,
                max_requests=args.max_requests,
                default_delay=args.delay,
                persist_db=args.persist_db,
                state_file=args.state_file,
                resume_from_state=args.resume,
            )
        )


if __name__ == "__main__":
    main()
