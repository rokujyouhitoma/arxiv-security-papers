"""High-Level Fluent DSL and Decorator API for simple user spiders."""

from __future__ import annotations

import asyncio
from typing import Any, AsyncIterator, Callable, List, Optional, Sequence, Set, Union

from .core.downloader import Request, Response
from .core.engine import Engine, ScrapedItem
from .core.scheduler import Scheduler
from .downloader.middleware import (
    HttpCacheMiddleware,
    RobotsTxtMiddleware,
    UserAgentMiddleware,
)
from .spiders.base import BaseSpider


class FunctionalSpider(BaseSpider):
    """Dynamically configured spider from functional definitions or builder."""

    def __init__(
        self,
        name: str,
        start_urls: Sequence[str],
        parse_fn: Callable[..., Any],
        allowed_domains: Optional[Set[str]] = None,
    ) -> None:
        self.name = name
        self.start_urls = list(start_urls)
        self.parse_fn = parse_fn
        self.allowed_domains = allowed_domains or set()

    async def _yield_async_result(self, result: Any, url: str) -> AsyncIterator[Union[Request, ScrapedItem]]:
        async for item in result:
            yield _coerce_to_item_or_request(item, url)

    async def _yield_sync_result(self, result: Any, url: str) -> AsyncIterator[Union[Request, ScrapedItem]]:
        if isinstance(result, (list, tuple, set)):
            for item in result:
                yield _coerce_to_item_or_request(item, url)
        elif result is not None:
            yield _coerce_to_item_or_request(result, url)

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        result = self.parse_fn(response)
        if asyncio.iscoroutine(result) or hasattr(result, "__anext__"):
            async for item in self._yield_async_result(result, response.url):
                yield item
        else:
            async for item in self._yield_sync_result(result, response.url):
                yield item


def _coerce_to_item_or_request(
    obj: Any, current_url: str
) -> Union[Request, ScrapedItem]:
    """Coerces dictionaries or primitive objects into ScrapedItem or Request."""
    if isinstance(obj, (Request, ScrapedItem)):
        return obj
    if isinstance(obj, dict):
        title = obj.get("title", "Untitled")
        item_id = obj.get("id") or obj.get("clean_id") or f"item_{abs(hash(title))}"
        return ScrapedItem(
            item_id=str(item_id),
            source_url=obj.get("url", current_url),
            title=str(title),
            payload=obj,
        )
    return ScrapedItem(
        item_id=f"item_{abs(hash(str(obj)))}",
        source_url=current_url,
        title=str(obj),
        payload={"value": obj},
    )


class SpiderBuilder:
    """Fluent Builder for configuring and running spiders in minimal lines of code."""

    def __init__(self, name: str = "quick_spider") -> None:
        self._name = name
        self._start_urls: List[str] = []
        self._allowed_domains: Set[str] = set()
        self._parse_fn: Optional[Callable[..., Any]] = None
        self._enable_cache: bool = False
        self._autothrottle: bool = True
        self._min_delay: float = 0.5
        self._max_requests: Optional[int] = None

    def start_url(self, url: str) -> "SpiderBuilder":
        self._start_urls.append(url)
        return self

    def start_urls(self, *urls: str) -> "SpiderBuilder":
        self._start_urls.extend(urls)
        return self

    def allowed_domains(self, *domains: str) -> "SpiderBuilder":
        self._allowed_domains.update(domains)
        return self

    def parse_with(self, fn: Callable[..., Any]) -> "SpiderBuilder":
        self._parse_fn = fn
        return self

    def with_cache(self, enabled: bool = True) -> "SpiderBuilder":
        self._enable_cache = enabled
        return self

    def with_rate_limit(self, min_delay: float = 0.5) -> "SpiderBuilder":
        self._min_delay = min_delay
        return self

    def limit(self, max_requests: int) -> "SpiderBuilder":
        self._max_requests = max_requests
        return self

    def build(self) -> FunctionalSpider:
        if not self._parse_fn:
            raise ValueError(
                "parse_with handler function must be provided before build."
            )
        return FunctionalSpider(
            name=self._name,
            start_urls=self._start_urls,
            parse_fn=self._parse_fn,
            allowed_domains=self._allowed_domains,
        )

    def run(self) -> List[ScrapedItem]:
        """Synchronously executes the spider using an event loop."""
        spider = self.build()
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
        return loop.run_until_complete(self.run_async(spider))

    async def run_async(
        self, spider: Optional[FunctionalSpider] = None
    ) -> List[ScrapedItem]:
        """Asynchronously executes the configured spider."""
        active_spider = spider or self.build()
        scheduler = Scheduler(default_delay=self._min_delay)
        engine = Engine(scheduler=scheduler)

        middlewares = [
            UserAgentMiddleware("ArxivSecurityResearchBot/1.0"),
            RobotsTxtMiddleware(),
        ]
        if self._enable_cache:
            middlewares.append(HttpCacheMiddleware())

        return await engine.crawl(
            spider=active_spider,
            middlewares=middlewares,
            max_requests=self._max_requests,
        )


def spider(
    *start_urls: str,
    name: str = "decorated_spider",
    allowed_domains: Optional[Sequence[str]] = None,
    min_delay: float = 0.5,
    max_requests: Optional[int] = None,
    enable_cache: bool = False,
) -> Callable[[Callable[..., Any]], SpiderBuilder]:
    """
    Decorator that transforms a standard parse function into a runnable SpiderBuilder.

    Example:
        @spider("https://arxiv.org/list/cs.CR/recent", allowed_domains=["arxiv.org"])
        def parse_security_papers(response):
            for link in response.css("h1.title"):
                yield {"title": link.text, "url": response.url}

        items = parse_security_papers.run()
    """

    def decorator(fn: Callable[..., Any]) -> SpiderBuilder:
        builder = (
            SpiderBuilder(name=name)
            .start_urls(*start_urls)
            .parse_with(fn)
            .with_rate_limit(min_delay)
            .with_cache(enable_cache)
        )
        if allowed_domains:
            builder.allowed_domains(*allowed_domains)
        if max_requests is not None:
            builder.limit(max_requests)
        return builder

    return decorator


def scrape(
    url: str,
    parse_fn: Callable[..., Any],
    min_delay: float = 0.0,
    enable_cache: bool = False,
) -> List[ScrapedItem]:
    """One-liner utility to crawl a single URL with a given parsing function."""
    builder = (
        SpiderBuilder()
        .start_url(url)
        .parse_with(parse_fn)
        .with_rate_limit(min_delay)
        .with_cache(enable_cache)
        .limit(1)
    )
    return builder.run()
