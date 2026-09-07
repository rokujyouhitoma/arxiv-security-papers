"""Unit tests for Response.json, Request.params, and Spider download_delay propagation."""

from __future__ import annotations

import json
from typing import AsyncIterator, Union
from unittest.mock import patch

import pytest

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.registry import get_spider_registry
from spider.runner import run_spider
from spider.spiders.base import BaseSpider


def test_response_json_success() -> None:
    """Test Response.json() returns parsed Python object for valid JSON."""
    payload = {
        "cve_id": "CVE-2026-1234",
        "score": 9.8,
        "active": True,
        "tags": ["kev", "rce"],
    }
    raw_body = json.dumps(payload).encode("utf-8")

    req = Request(url="https://api.example.com/cve")
    resp = Response(
        url="https://api.example.com/cve",
        status_code=200,
        headers={"content-type": "application/json"},
        body=raw_body,
        request=req,
    )

    parsed = resp.json()
    assert parsed == payload


def test_response_json_array() -> None:
    """Test Response.json() works with JSON lists."""
    payload = [{"id": 1}, {"id": 2}]
    req = Request(url="https://api.example.com/list")
    resp = Response(
        url="https://api.example.com/list",
        status_code=200,
        headers={},
        body=json.dumps(payload).encode("utf-8"),
        request=req,
    )
    assert resp.json() == payload


def test_response_json_invalid() -> None:
    """Test Response.json() raises JSONDecodeError on non-JSON content."""
    req = Request(url="https://api.example.com/html")
    resp = Response(
        url="https://api.example.com/html",
        status_code=200,
        headers={},
        body=b"<html><body>Not JSON</body></html>",
        request=req,
    )
    with pytest.raises(json.JSONDecodeError):
        resp.json()


def test_request_params_empty() -> None:
    """Test Request URL remains unchanged when params is None or empty."""
    req1 = Request(url="https://example.com/api")
    assert req1.url == "https://example.com/api"

    req2 = Request(url="https://example.com/api", params={})
    assert req2.url == "https://example.com/api"


def test_request_params_added() -> None:
    """Test Request attaches params properly to clean URL."""
    req = Request(
        url="https://services.nvd.nist.gov/rest/json/cves/2.0",
        params={"resultsPerPage": 2000, "startIndex": 4000},
    )
    assert "resultsPerPage=2000" in req.url
    assert "startIndex=4000" in req.url
    assert req.url.startswith("https://services.nvd.nist.gov/rest/json/cves/2.0?")


def test_request_params_merge_with_existing_query() -> None:
    """Test Request merges params with existing URL query string."""
    req = Request(
        url="https://example.com/search?q=security&page=1",
        params={"page": 2, "sort": "desc"},
    )
    assert "q=security" in req.url
    assert "page=2" in req.url  # Overwritten or updated
    assert "sort=desc" in req.url


def test_request_params_url_encoding() -> None:
    """Test Request params urlencodes special characters safely."""
    req = Request(
        url="https://example.com/query",
        params={"keyword": "zero day & exploit", "cve": "CVE-2026/001"},
    )
    assert "zero+day+%26+exploit" in req.url or "zero%20day%20%26%20exploit" in req.url
    assert "CVE-2026%2F001" in req.url


def test_base_spider_attributes() -> None:
    """Test BaseSpider default attributes and custom inheritance."""

    class CustomSpider(BaseSpider):
        name = "custom_test"
        download_delay = 6.5
        custom_settings = {"USER_AGENT": "CustomUA"}

        async def parse(
            self, response: Response
        ) -> AsyncIterator[Union[Request, ScrapedItem]]:
            yield  # type: ignore[misc]

    spider1 = CustomSpider()
    spider2 = CustomSpider()

    assert spider1.download_delay == 6.5
    assert spider1.custom_settings["USER_AGENT"] == "CustomUA"

    # Ensure mutable custom_settings is not shared
    spider1.custom_settings["NEW_KEY"] = "val"
    assert "NEW_KEY" not in spider2.custom_settings


def test_run_spider_delay_propagation() -> None:
    """Test run_spider prioritizes spider's download_delay over default 0.5."""

    async def _run() -> None:
        class PolitenessSpider(BaseSpider):
            name = "polite_test_spider"
            download_delay = 8.5

            async def parse(
                self, response: Response
            ) -> AsyncIterator[Union[Request, ScrapedItem]]:
                yield  # type: ignore[misc]

        registry = get_spider_registry()
        registry.register("polite_test_spider", PolitenessSpider)

        with patch("spider.runner.Engine.crawl") as mock_crawl:
            mock_crawl.return_value = []
            with patch("spider.runner.Scheduler") as mock_scheduler_cls:
                with patch("spider.runner._build_spider_middlewares") as mock_build_mid:
                    mock_build_mid.return_value = []
                    await run_spider("polite_test_spider", default_delay=0.5)

                    # Verify Scheduler was instantiated with effective_delay = 8.5
                    mock_scheduler_cls.assert_called_once_with(default_delay=8.5)
                    # Verify middlewares were built with effective_delay = 8.5
                    mock_build_mid.assert_called_once_with(8.5, True)

    import asyncio

    asyncio.run(_run())
