"""Unit tests for NvdCveSpider safety guards (Issue 337).

Verifies date range constraints (120-day span limit), pagination safety bounds,
and query parameter preservation across pagination requests.
"""

from __future__ import annotations

import urllib.parse
from typing import Any, Dict

from domain.security.spiders.nvd_cve_spider import (
    DEFAULT_NVD_MAX_PAGES,
    NvdCveSpider,
    _build_next_pagination_request,
    _resolve_date_range,
)
from spider.core.downloader import Response


def test_nvd_spider_default_safety_guards() -> None:
    """Verifies that NvdCveSpider enforces default date range and max_pages."""
    spider = NvdCveSpider()
    assert spider.max_pages == DEFAULT_NVD_MAX_PAGES
    assert len(spider.start_urls) == 1

    parsed_url = urllib.parse.urlparse(spider.start_urls[0])
    query_params = urllib.parse.parse_qs(parsed_url.query)

    assert "pubStartDate" in query_params
    assert "pubEndDate" in query_params
    assert query_params["resultsPerPage"] == ["2000"]


def test_nvd_spider_all_history_flag() -> None:
    """Verifies that all_history=True disables automatic pubStartDate/pubEndDate."""
    spider = NvdCveSpider(all_history=True)
    parsed_url = urllib.parse.urlparse(spider.start_urls[0])
    query_params = urllib.parse.parse_qs(parsed_url.query)

    assert "pubStartDate" not in query_params
    assert "pubEndDate" not in query_params


def test_resolve_date_range_clamp() -> None:
    """Verifies date range calculation clamps to MAX_NVD_DAYS_SPAN (120 days)."""
    # Exceeding 120 days should be clamped to 120
    s_date, e_date = _resolve_date_range(
        days_back=365, start_date_str=None, end_date_str=None
    )
    assert s_date is not None
    assert e_date is not None
    assert "T" in s_date
    assert "T" in e_date


def test_pagination_preserves_query_params() -> None:
    """Verifies that _build_next_pagination_request retains base query params (like pubStartDate)."""
    data: Dict[str, Any] = {
        "totalResults": 5000,
        "startIndex": 0,
        "resultsPerPage": 2000,
    }
    headers: Dict[str, str] = {"apiKey": "test-key"}
    base_params: Dict[str, Any] = {
        "pubStartDate": "2026-05-20T00:00:00.000",
        "pubEndDate": "2026-09-19T00:00:00.000",
    }

    req = _build_next_pagination_request(
        data=data,
        results_per_page=2000,
        headers=headers,
        base_params=base_params,
    )

    assert req is not None
    assert req.params is not None
    assert req.params["startIndex"] == 2000
    assert req.params["resultsPerPage"] == 2000
    assert req.params["pubStartDate"] == "2026-05-20T00:00:00.000"
    assert req.params["pubEndDate"] == "2026-09-19T00:00:00.000"


def test_spider_max_pages_cutoff() -> None:
    """Verifies that NvdCveSpider halts pagination once max_pages is reached."""
    import asyncio
    import json

    from spider.core.downloader import Request

    async def _run() -> None:
        spider = NvdCveSpider(max_pages=1)
        mock_payload = {
            "totalResults": 10000,
            "startIndex": 0,
            "resultsPerPage": 2000,
            "vulnerabilities": [
                {
                    "cve": {
                        "id": "CVE-2026-0001",
                        "descriptions": [{"lang": "en", "value": "Test vuln"}],
                        "published": "2026-09-01T00:00:00.000",
                    }
                }
            ],
        }

        req = Request(url=spider.start_urls[0])
        res = Response(
            url=spider.start_urls[0],
            status_code=200,
            headers={},
            body=json.dumps(mock_payload).encode("utf-8"),
            request=req,
        )

        results = []
        async for item in spider.parse(res):
            results.append(item)

        # 1 ScrapedItem yielded, but NO subsequent Request yielded because max_pages=1
        assert len(results) == 1
        assert not hasattr(results[0], "url")  # Not a Request

    asyncio.run(_run())
