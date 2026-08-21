"""Unit tests for Spider Core: BloomFilter, Selector, Scheduler, and Engine."""

import asyncio

from src.spider.core.bloom import BloomFilter, ScalableBloomFilter
from src.spider.core.downloader import AsyncHttpDownloader, Request, Response
from src.spider.core.engine import Engine, ScrapedItem
from src.spider.core.scheduler import Scheduler
from src.spider.core.selector import Selector
from src.spider.spiders.base import BaseSpider


def test_bloom_filter_basic() -> None:
    bf = BloomFilter(capacity=1000, error_rate=0.001)
    assert len(bf) == 0
    assert bf.add("https://arxiv.org/abs/2608.0001") is True
    assert bf.add("https://arxiv.org/abs/2608.0001") is False
    assert "https://arxiv.org/abs/2608.0001" in bf
    assert "https://arxiv.org/abs/2608.0002" not in bf
    assert len(bf) == 1


def test_scalable_bloom_filter_scaling() -> None:
    sbf = ScalableBloomFilter(initial_capacity=10, scale_factor=2)
    for i in range(50):
        sbf.add(f"https://example.com/{i}")

    assert len(sbf) == 50
    assert "https://example.com/10" in sbf
    assert "https://example.com/99" not in sbf


def test_pure_dom_parser_and_selector() -> None:
    html = """
    <html>
        <body>
            <div id="main" class="container dark">
                <h1 class="title">Security Paper</h1>
                <p class="summary">A novel zero-trust protocol.</p>
                <div class="authors">
                    <span class="author">Alice</span>
                    <span class="author">Bob</span>
                </div>
                <a id="download" href="https://example.com/paper.pdf" class="btn primary">Download PDF</a>
            </div>
        </body>
    </html>
    """
    selector = Selector(html)
    title_nodes = selector.css("h1.title")
    assert len(title_nodes) == 1
    assert title_nodes[0].text == "Security Paper"

    authors = selector.css("div.authors span.author")
    assert len(authors) == 2
    assert authors[0].text == "Alice"
    assert authors[1].text == "Bob"

    link = selector.css("a#download")
    assert len(link) == 1
    assert link[0].get_attr("href") == "https://example.com/paper.pdf"
    assert "btn" in link[0].get_attr("class")


def test_scheduler_priority_and_politeness() -> None:
    scheduler = Scheduler(default_delay=0.1)
    req1 = Request(url="https://arxiv.org/abs/1", priority=10)
    req2 = Request(url="https://arxiv.org/abs/2", priority=50)
    req3 = Request(url="https://iacr.org/1", priority=30)

    assert scheduler.enqueue(req1) is True
    assert scheduler.enqueue(req2) is True
    assert scheduler.enqueue(req3) is True
    assert scheduler.enqueue(req1) is False  # Duplicate in bloom

    # Next request should be highest priority (req2: 50)
    first = scheduler.next_request()
    assert first is not None
    assert first.url == "https://arxiv.org/abs/2"


class MockSpider(BaseSpider):
    name = "mock_spider"
    start_urls = ["https://mock.example.com/start"]

    async def parse(self, response: Response):
        yield ScrapedItem(
            item_id="mock_1",
            source_url=response.url,
            title="Mock Title",
            payload={"abstract": "Mock Abstract", "tags": ["test"]},
        )
        yield Request(url="https://mock.example.com/child", callback="parse_child")

    async def parse_child(self, response: Response):
        yield ScrapedItem(
            item_id="mock_2",
            source_url=response.url,
            title="Child Title",
            payload={"abstract": "Child Abstract"},
        )


class MockDownloader(AsyncHttpDownloader):
    async def download(self, request: Request) -> Response:
        return Response(
            url=request.url,
            status_code=200,
            headers={"content-type": "text/html"},
            body=b"<html><body><h1>Test</h1></body></html>",
            request=request,
            download_latency=0.01,
        )


def test_engine_crawl_lifecycle() -> None:
    async def _run() -> None:
        downloader = MockDownloader()
        scheduler = Scheduler(default_delay=0.0)
        engine = Engine(downloader=downloader, scheduler=scheduler)
        spider = MockSpider()

        items = await engine.crawl(spider=spider, max_requests=5)
        assert len(items) == 2
        assert items[0].title == "Mock Title"
        assert items[1].title == "Child Title"
        stats = engine.get_stats()
        assert stats["items_scraped"] == 2
        assert stats["responses_received"] == 2

    asyncio.run(_run())
