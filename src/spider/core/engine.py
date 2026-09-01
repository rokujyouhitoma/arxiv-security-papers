"""Event-driven Async Spider Engine orchestrating dataflow and signals."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Sequence, Union

from .downloader import AsyncHttpDownloader, Request, Response
from .scheduler import Scheduler


@dataclass
class ScrapedItem:
    """Represents a validated structured scraped item."""

    item_id: str
    source_url: str
    title: str
    payload: Dict[str, Any]
    scraped_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class Engine:
    """Core Async Engine managing scheduling, downloading, parsing, and pipeline flow."""

    def __init__(
        self,
        downloader: Optional[AsyncHttpDownloader] = None,
        scheduler: Optional[Scheduler] = None,
        max_concurrent_requests: int = 16,
    ) -> None:
        self.downloader: AsyncHttpDownloader = downloader or AsyncHttpDownloader()
        self.scheduler: Scheduler = scheduler or Scheduler()
        self.max_concurrent_requests: int = max_concurrent_requests
        self.running: bool = False
        self._stats: Dict[str, Union[int, float]] = {
            "requests_scheduled": 0,
            "responses_received": 0,
            "items_scraped": 0,
            "bytes_downloaded": 0,
        }

    async def _step_crawl(
        self,
        spider: Any,
        mid_list: List[Any],
        pipe_list: List[Any],
        scraped_items: List[ScrapedItem],
    ) -> bool:
        request = self.scheduler.next_request()
        if request is None:
            await asyncio.sleep(0.05)
            return False

        return await self._process_single_request(
            request, spider, mid_list, pipe_list, scraped_items
        )

    def _should_continue_crawling(self, max_requests: Optional[int], count: int) -> bool:
        if not (self.running and self.scheduler.has_pending_requests()):
            return False
        return not bool(max_requests and count >= max_requests)

    async def crawl(
        self,
        spider: Any,
        pipelines: Optional[Sequence[Any]] = None,
        middlewares: Optional[Sequence[Any]] = None,
        max_requests: Optional[int] = None,
    ) -> List[ScrapedItem]:
        """Runs the crawling loop for the given spider until completion or limit."""
        self.running = True
        scraped_items: List[ScrapedItem] = []
        pipe_list = list(pipelines or [])
        mid_list = list(middlewares or [])

        _enqueue_start_urls(spider, self.scheduler, self._stats)

        processed_count = 0
        while self._should_continue_crawling(max_requests, processed_count):
            if await self._step_crawl(spider, mid_list, pipe_list, scraped_items):
                processed_count += 1

        self.running = False
        return scraped_items

    async def _process_single_request(
        self,
        request: Request,
        spider: Any,
        mid_list: List[Any],
        pipe_list: List[Any],
        scraped_items: List[ScrapedItem],
    ) -> bool:
        response = await _fetch_response(request, spider, mid_list, self.downloader)
        if response is None:
            return False

        self._stats["responses_received"] = int(self._stats["responses_received"]) + 1
        self._stats["bytes_downloaded"] = int(self._stats["bytes_downloaded"]) + len(
            response.body
        )

        response = await _execute_middlewares_resp(request, response, spider, mid_list)
        await _dispatch_spider_callback(
            request,
            response,
            spider,
            self.scheduler,
            pipe_list,
            scraped_items,
            self._stats,
        )
        return True

    def get_stats(self) -> Dict[str, Union[int, float]]:
        return dict(self._stats)


def _enqueue_start_urls(
    spider: Any, scheduler: Scheduler, stats: Dict[str, Union[int, float]]
) -> None:
    start_urls: Sequence[str] = getattr(spider, "start_urls", [])
    for url in start_urls:
        req = Request(url=url, callback="parse")
        if scheduler.enqueue(req):
            stats["requests_scheduled"] = int(stats["requests_scheduled"]) + 1


async def _fetch_response(
    request: Request, spider: Any, mid_list: List[Any], downloader: AsyncHttpDownloader
) -> Optional[Response]:
    response = await _execute_middlewares_req(request, spider, mid_list)
    if response is None:
        try:
            return await downloader.download(request)
        except Exception:
            return None
    return response


async def _handle_results_async(
    results: Any,
    scheduler: Scheduler,
    pipe_list: List[Any],
    spider: Any,
    scraped_items: List[ScrapedItem],
    stats: Dict[str, Union[int, float]],
) -> None:
    async for res in results:
        await _handle_result(res, scheduler, pipe_list, spider, scraped_items, stats)


async def _handle_results_sync(
    results: Any,
    scheduler: Scheduler,
    pipe_list: List[Any],
    spider: Any,
    scraped_items: List[ScrapedItem],
    stats: Dict[str, Union[int, float]],
) -> None:
    for res in results:
        await _handle_result(res, scheduler, pipe_list, spider, scraped_items, stats)


async def _dispatch_spider_callback(
    request: Request,
    response: Response,
    spider: Any,
    scheduler: Scheduler,
    pipe_list: List[Any],
    scraped_items: List[ScrapedItem],
    stats: Dict[str, Union[int, float]],
) -> None:
    callback_fn = getattr(spider, request.callback, None)
    if callback_fn is None:
        return

    results = callback_fn(response)
    if asyncio.iscoroutine(results) or hasattr(results, "__anext__"):
        await _handle_results_async(results, scheduler, pipe_list, spider, scraped_items, stats)
    else:
        await _handle_results_sync(results, scheduler, pipe_list, spider, scraped_items, stats)


async def _execute_middlewares_req(
    request: Request, spider: Any, middlewares: List[Any]
) -> Optional[Response]:
    for mid in middlewares:
        if hasattr(mid, "process_request"):
            res = await mid.process_request(request, spider)
            if res is not None:
                return res  # type: ignore[no-any-return]
    return None


async def _execute_middlewares_resp(
    request: Request, response: Response, spider: Any, middlewares: List[Any]
) -> Response:
    current_resp = response
    for mid in reversed(middlewares):
        if hasattr(mid, "process_response"):
            current_resp = await mid.process_response(request, current_resp, spider)
    return current_resp


async def _process_item_pipelines(item: ScrapedItem, pipelines: List[Any], spider: Any) -> ScrapedItem:
    current_item = item
    for pipe in pipelines:
        if hasattr(pipe, "process_item"):
            current_item = await pipe.process_item(current_item, spider)
    return current_item


async def _handle_result(
    res: Any,
    scheduler: Scheduler,
    pipelines: List[Any],
    spider: Any,
    scraped_items: List[ScrapedItem],
    stats: Dict[str, Union[int, float]],
) -> None:
    if isinstance(res, Request):
        if scheduler.enqueue(res):
            stats["requests_scheduled"] = int(stats["requests_scheduled"]) + 1
    elif isinstance(res, ScrapedItem):
        item = await _process_item_pipelines(res, pipelines, spider)
        scraped_items.append(item)
        stats["items_scraped"] = int(stats["items_scraped"]) + 1
