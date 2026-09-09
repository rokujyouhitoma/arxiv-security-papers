"""Spider CLI Runner - User code entrypoint for executing and managing spiders."""

from __future__ import annotations

import argparse
import asyncio
import os
from typing import Any, Callable, Dict, List, Optional, Sequence, cast

from .core.downloader import AsyncHttpDownloader
from .core.engine import Engine, ScrapedItem
from .core.scheduler import Scheduler
from .distributed.state_storage import StateStorage
from .downloader.middleware import (
    HttpCacheMiddleware,
    OffsiteMiddleware,
    RetryMiddleware,
    RobotsTxtMiddleware,
    UserAgentMiddleware,
)
from .pipeline.base import (
    ConsoleItemPipeline,
    JsonLinesItemPipeline,
    get_pipeline_registry,
)
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


def _build_spider_middlewares(
    default_delay: float,
    enable_cache: bool,
    downloader: Optional[AsyncHttpDownloader] = None,
) -> List[Any]:
    middlewares: List[Any] = [
        OffsiteMiddleware(),
        UserAgentMiddleware(),
        RobotsTxtMiddleware(),
        AutoThrottlePolicy(min_delay=default_delay),
    ]
    if enable_cache:
        middlewares.append(HttpCacheMiddleware())
    middlewares.append(RetryMiddleware(downloader=downloader))
    return middlewares


def _resolve_spider_instance(spider_name: str) -> BaseSpider:
    avail = get_available_spiders()
    if spider_name not in avail:
        raise ValueError(
            f"Unknown spider: {spider_name}. Available: {list(avail.keys())}"
        )
    return avail[spider_name]()


def _resolve_effective_delay(
    spider_instance: BaseSpider, default_delay: float
) -> float:
    spider_delay = getattr(spider_instance, "download_delay", 0.5)
    return default_delay if default_delay != 0.5 else spider_delay


def _inject_downloader_to_middlewares(
    middlewares: List[Any], downloader: AsyncHttpDownloader
) -> None:
    for mid in middlewares:
        if isinstance(mid, RetryMiddleware) and mid.downloader is None:
            mid.downloader = downloader


_SECURITY_SPIDER_NAMES = {
    "arxiv",
    "arxiv_spider",
    "iacr",
    "iacr_spider",
    "advisory",
    "advisory_spider",
    "cisa_kev",
    "cisa_kev_spider",
    "nvd_cve",
    "nvd_cve_spider",
}


def _is_security_spider_or_output(spider_name: str, output_dir: Optional[str]) -> bool:
    if spider_name in _SECURITY_SPIDER_NAMES:
        return True
    return bool(output_dir and "okf" in output_dir)


def _resolve_okf_pipeline(output_dir: Optional[str], persist_db: bool) -> List[Any]:
    pipe_reg = get_pipeline_registry()
    okf_cls = pipe_reg.get("okf")
    if okf_cls is not None:
        factory = cast(Any, okf_cls)
        return [
            factory(
                output_dir=output_dir or "outputs/okf_papers",
                enable_db_persistence=persist_db,
            )
        ]
    from domain.security.pipeline.okf_pipeline import SecurityOkfItemPipeline

    return [
        SecurityOkfItemPipeline(
            output_dir=output_dir or "outputs/okf_papers",
            enable_db_persistence=persist_db,
        )
    ]


def _resolve_by_type(
    pipeline_type: str, output_dir: Optional[str], persist_db: bool
) -> Optional[List[Any]]:
    ptype = pipeline_type.lower()
    if ptype == "jsonl":
        return [JsonLinesItemPipeline(output_dir=output_dir or "outputs/scraped_data")]
    if ptype == "console":
        return [ConsoleItemPipeline()]
    if ptype in ("okf", "security_okf"):
        return _resolve_okf_pipeline(output_dir, persist_db)
    return None


def _resolve_injected_pipelines(
    pipelines: Optional[Sequence[Any]],
    pipeline_factory: Optional[Callable[..., Sequence[Any]]],
) -> Optional[List[Any]]:
    if pipelines is not None:
        return list(pipelines)
    if pipeline_factory is not None:
        return list(pipeline_factory())
    return None


def _resolve_default_pipeline(
    spider_name: str, output_dir: Optional[str], persist_db: bool
) -> List[Any]:
    if _is_security_spider_or_output(spider_name, output_dir):
        return _resolve_okf_pipeline(output_dir, persist_db)
    target_dir = output_dir if output_dir else "outputs/scraped_data"
    return [JsonLinesItemPipeline(output_dir=target_dir)]


def _resolve_pipelines(
    spider_name: str,
    output_dir: Optional[str],
    persist_db: bool,
    pipelines: Optional[Sequence[Any]] = None,
    pipeline_factory: Optional[Callable[..., Sequence[Any]]] = None,
    pipeline_type: Optional[str] = None,
) -> List[Any]:
    """Resolves item pipelines using dependency injection, CLI type, or auto resolution."""
    injected = _resolve_injected_pipelines(pipelines, pipeline_factory)
    if injected is not None:
        return injected
    typed = (
        _resolve_by_type(pipeline_type, output_dir, persist_db)
        if pipeline_type
        else None
    )
    if typed is not None:
        return typed
    return _resolve_default_pipeline(spider_name, output_dir, persist_db)


async def run_spider(
    spider_name: str,
    output_dir: Optional[str] = None,
    max_requests: Optional[int] = None,
    default_delay: float = 0.5,
    enable_cache: bool = True,
    persist_db: bool = False,
    state_file: Optional[str] = None,
    resume_from_state: bool = False,
    pipelines: Optional[Sequence[Any]] = None,
    pipeline_factory: Optional[Callable[..., Sequence[Any]]] = None,
    pipeline_type: Optional[str] = None,
) -> List[ScrapedItem]:
    """Runs a specific spider with full middleware and DI-injected pipeline stack."""
    spider_instance = _resolve_spider_instance(spider_name)
    effective_delay = _resolve_effective_delay(spider_instance, default_delay)

    scheduler = Scheduler(default_delay=effective_delay)
    _init_scheduler_state(scheduler, state_file, resume_from_state)

    downloader = AsyncHttpDownloader()
    engine = Engine(downloader=downloader, scheduler=scheduler)
    middlewares = _build_spider_middlewares(effective_delay, enable_cache)
    _inject_downloader_to_middlewares(middlewares, downloader)

    resolved_pipelines = _resolve_pipelines(
        spider_name=spider_name,
        output_dir=output_dir,
        persist_db=persist_db,
        pipelines=pipelines,
        pipeline_factory=pipeline_factory,
        pipeline_type=pipeline_type,
    )

    pipe_count = len(resolved_pipelines)
    url_count = len(spider_instance.start_urls)
    print(
        f"[*] Starting Spider: '{spider_name}' "
        f"(start_urls: {url_count}, pipelines: {pipe_count})"
    )
    items = await engine.crawl(
        spider=spider_instance,
        pipelines=resolved_pipelines,
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
    output_dir: Optional[str] = None,
    max_requests_per_spider: Optional[int] = None,
    persist_db: bool = False,
    pipelines: Optional[Sequence[Any]] = None,
    pipeline_type: Optional[str] = None,
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
            pipelines=pipelines,
            pipeline_type=pipeline_type,
        )
        results[name] = items
    return results


class SpiderRunner:
    """Synchronous orchestration wrapper for executing spiders."""

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        pipelines: Optional[Sequence[Any]] = None,
        pipeline_type: Optional[str] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or os.getcwd()
        self.output_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        self.pipelines = pipelines
        self.pipeline_type = pipeline_type

    def run_spider(
        self,
        spider_name: str,
        max_depth: Optional[int] = None,
        max_requests: Optional[int] = None,
        pipelines: Optional[Sequence[Any]] = None,
        output_dir: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Runs the spider synchronously and returns stats."""
        items = asyncio.run(
            run_spider(
                spider_name=spider_name,
                output_dir=output_dir or self.output_dir,
                max_requests=max_requests or max_depth,
                pipelines=pipelines or self.pipelines,
                pipeline_type=self.pipeline_type,
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
        "--pipeline",
        choices=["auto", "jsonl", "okf", "console"],
        default="auto",
        help="Item pipeline to apply (auto, jsonl, okf, console)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory for crawler output (defaults to outputs/okf_papers or outputs/scraped_data)",
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
    parser.add_argument(
        "--daemon", action="store_true", help="Start as resident SpiderDaemonWorker"
    )
    return parser.parse_args(args)


def _run_daemon_mode(worker_id: str = "daemon_cli") -> None:
    import time

    from .daemon.worker import SpiderDaemonWorker

    worker = SpiderDaemonWorker(worker_id=worker_id)
    print(
        f"[*] Started SpiderDaemonWorker [{worker_id}] in resident mode. "
        "Press Ctrl+C to drain."
    )
    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        print("[*] Draining SpiderDaemonWorker...")
        worker.drain()
        print("[+] Drain complete. Exiting.")


def _dispatch_spider_execution(
    args: argparse.Namespace, pipe_type: Optional[str]
) -> None:
    if args.spider == "all":
        asyncio.run(
            run_all_spiders(
                output_dir=args.output_dir,
                max_requests_per_spider=args.max_requests,
                persist_db=args.persist_db,
                pipeline_type=pipe_type,
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
                pipeline_type=pipe_type,
            )
        )


def main() -> None:
    args = parse_cli_args()
    if args.daemon:
        _run_daemon_mode()
        return
    pipe_type = None if args.pipeline == "auto" else args.pipeline
    _dispatch_spider_execution(args, pipe_type)


if __name__ == "__main__":
    main()
