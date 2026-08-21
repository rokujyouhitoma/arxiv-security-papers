"""Unit tests for Spider High-Level DSL and Decorator API."""

import asyncio

from src.spider.core.downloader import Request, Response
from src.spider.core.engine import ScrapedItem
from src.spider.dsl import FunctionalSpider, SpiderBuilder, spider


def test_spider_builder_fluent_api() -> None:
    def custom_parser(response: Response) -> list[dict[str, str]]:
        return [
            {
                "title": "Custom Security Paper",
                "url": response.url,
                "clean_id": "test.001",
            }
        ]

    builder = (
        SpiderBuilder(name="fluent_test")
        .start_url("https://arxiv.org/list/cs.CR/recent")
        .allowed_domains("arxiv.org")
        .with_rate_limit(0.1)
        .with_cache(True)
        .limit(5)
        .parse_with(custom_parser)
    )

    functional_spider = builder.build()
    assert isinstance(functional_spider, FunctionalSpider)
    assert functional_spider.name == "fluent_test"
    assert "https://arxiv.org/list/cs.CR/recent" in functional_spider.start_urls
    assert "arxiv.org" in functional_spider.allowed_domains

    async def _test_parse() -> None:
        req = Request(url="https://arxiv.org/list/cs.CR/recent")
        resp = Response(
            url=req.url, status_code=200, headers={}, body=b"<html></html>", request=req
        )
        items: list[ScrapedItem] = []
        async for item in functional_spider.parse(resp):
            if isinstance(item, ScrapedItem):
                items.append(item)
        assert len(items) == 1
        assert items[0].title == "Custom Security Paper"
        assert items[0].payload["clean_id"] == "test.001"

    asyncio.run(_test_parse())


def test_spider_decorator_api() -> None:
    @spider(
        "https://arxiv.org/abs/2401.00001",
        allowed_domains=["arxiv.org"],
        min_delay=0.1,
        max_requests=2,
    )
    def parse_paper(response: Response) -> dict[str, str]:
        return {
            "title": "Decorated Paper",
            "url": response.url,
            "id": "dec_2401.00001",
        }

    assert isinstance(parse_paper, SpiderBuilder)
    functional_spider = parse_paper.build()
    assert (
        functional_spider.name == "parse_paper"
        or functional_spider.name == "decorated_spider"
    )

    async def _test_parse() -> None:
        req = Request(url="https://arxiv.org/abs/2401.00001")
        resp = Response(
            url=req.url, status_code=200, headers={}, body=b"<html></html>", request=req
        )
        items: list[ScrapedItem] = []
        async for item in functional_spider.parse(resp):
            if isinstance(item, ScrapedItem):
                items.append(item)
        assert len(items) == 1
        assert items[0].title == "Decorated Paper"
        assert items[0].item_id == "dec_2401.00001"

    asyncio.run(_test_parse())


def test_scrape_one_liner_mock() -> None:
    def parse_one(response: Response) -> dict[str, str]:
        return {"title": "One Liner Result", "url": response.url}

    # Verify building and configuration
    builder = SpiderBuilder().start_url("https://example.com").parse_with(parse_one)
    assert builder._start_urls == ["https://example.com"]
