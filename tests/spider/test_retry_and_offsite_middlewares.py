"""Unit tests for OffsiteMiddleware (SSRF boundary defense) and RetryMiddleware (429/5xx backoff)."""

from __future__ import annotations

import asyncio
import datetime
from typing import AsyncIterator, List, Optional
from unittest.mock import AsyncMock

from spider.core.downloader import AsyncHttpDownloader, Request, Response
from spider.core.engine import Engine, ScrapedItem
from spider.core.scheduler import Scheduler
from spider.downloader.middleware import (
    OffsiteMiddleware,
    RetryMiddleware,
    _parse_retry_after,
)
from spider.runner import _build_spider_middlewares


class DummySpider:
    """Dummy spider for testing middlewares."""

    def __init__(self, allowed_domains: Optional[List[str]] = None) -> None:
        self.allowed_domains = allowed_domains
        self.start_urls: List[str] = []


# ============================================================================
# OffsiteMiddleware Tests
# ============================================================================


def test_offsite_middleware_allows_exact_domain() -> None:
    async def _test() -> None:
        middleware = OffsiteMiddleware()
        spider = DummySpider(allowed_domains=["example.com", "arxiv.org"])
        req = Request(url="https://example.com/paper/1234")

        res = await middleware.process_request(req, spider)
        assert res is None

    asyncio.run(_test())


def test_offsite_middleware_allows_subdomain() -> None:
    async def _test() -> None:
        middleware = OffsiteMiddleware()
        spider = DummySpider(allowed_domains=["example.com", "arxiv.org"])
        req = Request(url="https://export.arxiv.org/api/query?id=2608.1234")

        res = await middleware.process_request(req, spider)
        assert res is None

    asyncio.run(_test())


def test_offsite_middleware_blocks_external_domain() -> None:
    async def _test() -> None:
        middleware = OffsiteMiddleware()
        spider = DummySpider(allowed_domains=["example.com"])
        req = Request(url="https://evil.com/phishing")

        res = await middleware.process_request(req, spider)
        assert res is not None
        assert res.status_code == 403
        assert res.headers.get("X-Blocked-By") == "OffsiteMiddleware"
        assert b"Blocked by OffsiteMiddleware" in res.body

    asyncio.run(_test())


def test_offsite_middleware_blocks_private_and_metadata_ip() -> None:
    async def _test() -> None:
        middleware = OffsiteMiddleware()
        spider = DummySpider(allowed_domains=["example.com"])

        # Localhost
        res_local = await middleware.process_request(
            Request(url="http://127.0.0.1:8000/admin"), spider
        )
        assert res_local is not None
        assert res_local.status_code == 403

        # AWS/GCP metadata
        res_meta = await middleware.process_request(
            Request(url="http://169.254.169.254/latest/meta-data/"), spider
        )
        assert res_meta is not None
        assert res_meta.status_code == 403

    asyncio.run(_test())


def test_offsite_middleware_passes_when_allowed_domains_empty_or_none() -> None:
    async def _test() -> None:
        middleware = OffsiteMiddleware()

        # None allowed_domains
        spider_none = DummySpider(allowed_domains=None)
        assert (
            await middleware.process_request(
                Request(url="https://anywhere.com"), spider_none
            )
            is None
        )

        # Empty list allowed_domains
        spider_empty = DummySpider(allowed_domains=[])
        assert (
            await middleware.process_request(
                Request(url="https://anywhere.com"), spider_empty
            )
            is None
        )

    asyncio.run(_test())


# ============================================================================
# Retry-After Parsing Tests
# ============================================================================


def test_parse_retry_after_numeric() -> None:
    assert _parse_retry_after("10") == 10.0
    assert _parse_retry_after("2.5") == 2.5
    assert _parse_retry_after("0") == 0.0
    assert _parse_retry_after("-5") == 0.0


def test_parse_retry_after_http_date() -> None:
    # Future date (10 seconds from now)
    future = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(
        seconds=10
    )
    date_str = future.strftime("%a, %d %b %Y %H:%M:%S GMT")
    delta = _parse_retry_after(date_str)
    assert delta is not None
    assert 8.0 <= delta <= 12.0


def test_parse_retry_after_invalid() -> None:
    assert _parse_retry_after(None) is None
    assert _parse_retry_after("") is None
    assert _parse_retry_after("invalid-value-xyz") is None


# ============================================================================
# RetryMiddleware Tests
# ============================================================================


def test_retry_middleware_ignores_200_and_404() -> None:
    async def _test() -> None:
        middleware = RetryMiddleware()
        spider = DummySpider()
        req = Request(url="https://api.example.com/cve")

        # 200 OK
        resp_200 = Response(
            url=req.url, status_code=200, headers={}, body=b"OK", request=req
        )
        out_200 = await middleware.process_response(req, resp_200, spider)
        assert out_200.status_code == 200

        # 404 Not Found (not in retry_http_codes)
        resp_404 = Response(
            url=req.url, status_code=404, headers={}, body=b"Not Found", request=req
        )
        out_404 = await middleware.process_response(req, resp_404, spider)
        assert out_404.status_code == 404

    asyncio.run(_test())


def test_retry_middleware_recovers_on_429_with_retry_after() -> None:
    async def _test() -> None:
        req = Request(url="https://api.example.com/cve")
        resp_429 = Response(
            url=req.url,
            status_code=429,
            headers={"retry-after": "0.01"},
            body=b"Rate limited",
            request=req,
        )
        resp_200 = Response(
            url=req.url,
            status_code=200,
            headers={},
            body=b'{"status": "ok"}',
            request=req,
        )

        mock_downloader = AsyncMock(spec=AsyncHttpDownloader)
        mock_downloader.download.return_value = resp_200

        middleware = RetryMiddleware(
            max_retry_times=3, initial_delay=0.01, downloader=mock_downloader
        )
        spider = DummySpider()

        result = await middleware.process_response(req, resp_429, spider)

        assert result.status_code == 200
        assert result.body == b'{"status": "ok"}'
        assert req.meta.get("retry_times") == 1
        mock_downloader.download.assert_awaited_once_with(req)

    asyncio.run(_test())


def test_retry_middleware_max_retries_stop_loop() -> None:
    async def _test() -> None:
        req = Request(url="https://api.example.com/cve")
        resp_503 = Response(
            url=req.url,
            status_code=503,
            headers={},
            body=b"Service Unavailable",
            request=req,
        )

        mock_downloader = AsyncMock(spec=AsyncHttpDownloader)
        mock_downloader.download.return_value = resp_503

        middleware = RetryMiddleware(
            max_retry_times=3,
            initial_delay=0.001,
            backoff_factor=1.5,
            downloader=mock_downloader,
        )
        spider = DummySpider()

        result = await middleware.process_response(req, resp_503, spider)

        # After 3 retries, returns 503 without infinite loop
        assert result.status_code == 503
        assert req.meta.get("retry_times") == 3
        assert mock_downloader.download.await_count == 3

    asyncio.run(_test())


def test_retry_middleware_handles_download_exception() -> None:
    async def _test() -> None:
        req = Request(url="https://api.example.com/cve")
        resp_500 = Response(
            url=req.url,
            status_code=500,
            headers={},
            body=b"Server Error",
            request=req,
        )

        mock_downloader = AsyncMock(spec=AsyncHttpDownloader)
        mock_downloader.download.side_effect = ConnectionResetError(
            "Connection dropped"
        )

        middleware = RetryMiddleware(
            max_retry_times=2, initial_delay=0.001, downloader=mock_downloader
        )
        spider = DummySpider()

        result = await middleware.process_response(req, resp_500, spider)

        # Should safely capture exception as a 500 response and stop at max retries
        assert result.status_code == 500
        assert req.meta.get("retry_times") == 2

    asyncio.run(_test())


# ============================================================================
# Runner & Engine Middleware Stack Integration Tests
# ============================================================================


def test_build_spider_middlewares_order() -> None:
    downloader = AsyncHttpDownloader()
    mids = _build_spider_middlewares(
        default_delay=1.0, enable_cache=True, downloader=downloader
    )

    assert any(isinstance(m, OffsiteMiddleware) for m in mids)
    assert any(isinstance(m, RetryMiddleware) for m in mids)
    # OffsiteMiddleware should be first (index 0)
    assert isinstance(mids[0], OffsiteMiddleware)
    # RetryMiddleware should be last
    assert isinstance(mids[-1], RetryMiddleware)
    assert mids[-1].downloader is downloader


def test_engine_integration_with_offsite_and_retry() -> None:
    """Tests end-to-end flow with Engine dispatching through Offsite and Retry."""

    async def _test() -> None:
        class CveSpider:
            name = "cve_spider"
            allowed_domains = ["api.example.com"]
            start_urls = [
                "https://api.example.com/cve",
                "https://evil.com/ssrf",
            ]

            def parse(self, response: Response) -> AsyncIterator[ScrapedItem]:
                async def gen() -> AsyncIterator[ScrapedItem]:
                    if response.status_code == 200:
                        yield ScrapedItem(
                            item_id="CVE-2026-0001",
                            source_url=response.url,
                            title="Sample CVE",
                            payload={"status": "ok"},
                        )

                return gen()

        spider = CveSpider()
        mock_downloader = AsyncMock(spec=AsyncHttpDownloader)

        # Setup mock download response for api.example.com
        resp_429 = Response(
            url="https://api.example.com/cve",
            status_code=429,
            headers={"retry-after": "0.001"},
            body=b"Rate limit",
            request=Request(url="https://api.example.com/cve"),
        )
        resp_200 = Response(
            url="https://api.example.com/cve",
            status_code=200,
            headers={},
            body=b'{"id": "CVE-2026-0001"}',
            request=Request(url="https://api.example.com/cve"),
        )
        # First returns 429, then on retry returns 200
        mock_downloader.download.side_effect = [resp_429, resp_200]

        scheduler = Scheduler(default_delay=0.0)
        engine = Engine(downloader=mock_downloader, scheduler=scheduler)
        middlewares = [
            OffsiteMiddleware(),
            RetryMiddleware(
                max_retry_times=2, initial_delay=0.001, downloader=mock_downloader
            ),
        ]

        items = await engine.crawl(spider=spider, middlewares=middlewares)

        # Only 1 item scraped from api.example.com after 429 -> 200 recovery
        assert len(items) == 1
        assert items[0].item_id == "CVE-2026-0001"

        # evil.com request was blocked by OffsiteMiddleware, so downloader was NEVER called for evil.com
        for call_arg in mock_downloader.download.call_args_list:
            req = call_arg[0][0]
            assert "evil.com" not in req.url

    asyncio.run(_test())
