"""Unit tests for RFC 7232 Conditional GET and HTTP 304 Cache Transparency (Issue 209)."""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock

from spider.core.downloader import Request, Response, _should_have_body
from spider.downloader.middleware import HttpCacheMiddleware, _sanitize_header_value


def test_sanitize_header_value() -> None:
    """Tests header value sanitization against CRLF injection (CWE-113)."""
    assert _sanitize_header_value(None) is None
    assert _sanitize_header_value("") is None
    assert _sanitize_header_value(' "v1.2.3" ') == '"v1.2.3"'
    # CRLF Injection attempt
    evil = 'W/"123"\r\nInjected-Header: evil\nAnother: bad'
    sanitized = _sanitize_header_value(evil)
    assert "\r" not in sanitized
    assert "\n" not in sanitized
    assert "Injected-Header" in sanitized


def test_should_have_body() -> None:
    """Tests RFC 7230 Section 3.3.2 response body presence check."""
    assert not _should_have_body(304)
    assert not _should_have_body(204)
    assert not _should_have_body(100)
    assert not _should_have_body(101)
    assert _should_have_body(200)
    assert _should_have_body(404)
    assert _should_have_body(500)


def test_http_cache_initial_store_and_conditional_injection() -> None:
    """Tests caching of 200 OK and subsequent conditional request header injection."""

    async def _run() -> None:
        middleware = HttpCacheMiddleware(max_size=10)
        spider = MagicMock()

        url = "https://www.cisa.gov/known-exploited-vulnerabilities-catalog"
        req1 = Request(url=url)

        # 1. Initial request (cache miss)
        cached_resp = await middleware.process_request(req1, spider)
        assert cached_resp is None
        assert "If-None-Match" not in req1.headers
        assert "If-Modified-Since" not in req1.headers

        # 2. Server returns 200 OK with ETag & Last-Modified
        resp1 = Response(
            url=url,
            status_code=200,
            headers={
                "etag": '"cisa-kev-v2026-09-07"',
                "last-modified": "Mon, 07 Sep 2026 21:00:00 GMT",
                "content-type": "application/json",
            },
            body=b'{"title": "CISA KEV Catalog", "vulnerabilities": []}',
            request=req1,
        )
        returned_resp1 = await middleware.process_response(req1, resp1, spider)
        assert returned_resp1 is resp1
        assert url in middleware._cache
        entry = middleware._cache[url]
        assert entry.etag == '"cisa-kev-v2026-09-07"'
        assert entry.last_modified == "Mon, 07 Sep 2026 21:00:00 GMT"

        # 3. Subsequent request -> conditional headers injected, returns None for network fetch
        req2 = Request(url=url)
        res_req2 = await middleware.process_request(req2, spider)
        assert res_req2 is None
        assert req2.headers.get("If-None-Match") == '"cisa-kev-v2026-09-07"'
        assert req2.headers.get("If-Modified-Since") == "Mon, 07 Sep 2026 21:00:00 GMT"

    asyncio.run(_run())


def test_http_cache_304_transparent_body_synthesis() -> None:
    """Tests transparent restoration of cached body upon receiving 304 Not Modified."""

    async def _run() -> None:
        middleware = HttpCacheMiddleware()
        spider = MagicMock()
        url = "https://nvd.nist.gov/feeds/json/cve/2.0/recent.json"

        # Setup cached response
        original_body = b'{"format": "NVD_CVE", "CVE_Items": [1, 2, 3]}'
        req1 = Request(url=url)
        resp1 = Response(
            url=url,
            status_code=200,
            headers={"etag": '"nvd-v1.0"', "server": "cloudflare"},
            body=original_body,
            request=req1,
        )
        await middleware.process_response(req1, resp1, spider)

        # 2nd request sent with conditional headers
        req2 = Request(url=url)
        await middleware.process_request(req2, spider)
        assert req2.headers["If-None-Match"] == '"nvd-v1.0"'

        # Server responds 304 Not Modified with empty body
        resp_304 = Response(
            url=url,
            status_code=304,
            headers={"etag": '"nvd-v1.0"', "date": "Mon, 07 Sep 2026 22:00:00 GMT"},
            body=b"",
            request=req2,
            download_latency=0.045,
        )
        synthesized_resp = await middleware.process_response(req2, resp_304, spider)

        # Synthesized response must have status 200 and previous body
        assert synthesized_resp.status_code == 200
        assert synthesized_resp.body == original_body
        assert synthesized_resp.text == original_body.decode("utf-8")
        assert req2.meta.get("cached") is True
        assert req2.meta.get("validated_304") is True
        # Headers should be merged (updating date, keeping server)
        assert synthesized_resp.headers.get("server") == "cloudflare"
        assert "22:00:00" in synthesized_resp.headers.get("date", "")

    asyncio.run(_run())


def test_http_cache_force_cache_mode() -> None:
    """Tests force_cache=True returns cached response without network fetch."""

    async def _run() -> None:
        middleware = HttpCacheMiddleware()
        spider = MagicMock()
        url = "https://example.com/cached"

        req1 = Request(url=url)
        resp1 = Response(
            url=url,
            status_code=200,
            headers={},
            body=b"Cached Data",
            request=req1,
        )
        await middleware.process_response(req1, resp1, spider)

        # Request with force_cache=True
        req2 = Request(url=url, meta={"force_cache": True})
        direct_resp = await middleware.process_request(req2, spider)
        assert direct_resp is not None
        assert direct_resp.body == b"Cached Data"

    asyncio.run(_run())


def test_http_cache_use_cache_false_bypass() -> None:
    """Tests use_cache=False completely bypasses caching logic."""

    async def _run() -> None:
        middleware = HttpCacheMiddleware()
        spider = MagicMock()
        url = "https://example.com/no-cache"

        # Populate cache
        req1 = Request(url=url)
        resp1 = Response(
            url=url,
            status_code=200,
            headers={"etag": '"v1"'},
            body=b"Data",
            request=req1,
        )
        await middleware.process_response(req1, resp1, spider)

        # Request with use_cache=False
        req2 = Request(url=url, meta={"use_cache": False})
        res_req = await middleware.process_request(req2, spider)
        assert res_req is None
        assert "If-None-Match" not in req2.headers

        # Response with use_cache=False
        resp2 = Response(
            url=url,
            status_code=200,
            headers={"etag": '"v2"'},
            body=b"New Data",
            request=req2,
        )
        await middleware.process_response(req2, resp2, spider)
        # Entry in cache should remain old entry
        assert middleware._cache[url].etag == '"v1"'

    asyncio.run(_run())


def test_http_cache_max_size_eviction() -> None:
    """Tests eviction of oldest entries when cache size exceeds max_size."""

    async def _run() -> None:
        middleware = HttpCacheMiddleware(max_size=2)
        spider = MagicMock()

        for i in range(1, 4):
            url = f"https://example.com/{i}"
            req = Request(url=url)
            resp = Response(
                url=url,
                status_code=200,
                headers={"etag": f'"v{i}"'},
                body=f"Body {i}".encode("utf-8"),
                request=req,
            )
            await middleware.process_response(req, resp, spider)

        # Cache size must not exceed max_size
        assert len(middleware._cache) == 2
        # Earliest entry (url 1) must have been evicted
        assert "https://example.com/1" not in middleware._cache
        assert "https://example.com/2" in middleware._cache
        assert "https://example.com/3" in middleware._cache

    asyncio.run(_run())
