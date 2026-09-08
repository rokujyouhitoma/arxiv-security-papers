"""Unit tests for generic Item Pipelines, DropItem, and PipelineRegistry (Issue 210)."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import shutil
import tempfile
from typing import Any, AsyncIterator, Union

import pytest

from spider.core.downloader import Request, Response
from spider.core.engine import Engine, ScrapedItem
from spider.pipeline.base import (
    BaseItemPipeline,
    ConsoleItemPipeline,
    DropItem,
    JsonLinesItemPipeline,
    PipelineRegistry,
    _sanitize_filename,
)
from spider.runner import run_spider
from spider.spiders.base import BaseSpider


class DummyFilterPipeline(BaseItemPipeline):
    """Pipeline that drops items containing 'DROP' in title."""

    def __init__(self) -> None:
        self.opened = False
        self.closed = False

    async def open_spider(self, spider: Any) -> None:
        self.opened = True

    async def close_spider(self, spider: Any) -> None:
        self.closed = True

    async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
        if "DROP" in item.title:
            raise DropItem(f"Title contains DROP: {item.title}")
        item.payload["processed_by_dummy"] = True
        return item


class MockSimpleSpider(BaseSpider):
    name = "mock_simple_spider"
    start_urls = ["https://example.com/items"]

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        yield ScrapedItem(
            item_id="item_1",
            source_url="https://example.com/1",
            title="Valid Security Item 日本語",
            payload={"key": "val1"},
        )
        yield ScrapedItem(
            item_id="item_2",
            source_url="https://example.com/2",
            title="Item To DROP Now",
            payload={"key": "val2"},
        )


@pytest.fixture
def temp_dir() -> Any:
    td = tempfile.mkdtemp()
    yield td
    shutil.rmtree(td, ignore_errors=True)


def test_sanitize_filename() -> None:
    """Verifies CWE-22 Path Traversal prevention in filename generation."""
    assert _sanitize_filename("../../etc/passwd") == "etc_passwd"
    assert _sanitize_filename("spider/../../name") == "spider_name"
    assert _sanitize_filename("valid-name_01.ext") == "valid-name_01.ext"
    assert _sanitize_filename("") == "unnamed_spider"


def test_pipeline_registry_operations() -> None:
    """Verifies PipelineRegistry registration, discovery, creation, and listing."""
    reg = PipelineRegistry()
    assert "jsonl" in reg.list_pipelines()
    assert "console" in reg.list_pipelines()

    # Register custom pipeline class
    reg.register("dummy", DummyFilterPipeline)
    assert "dummy" in reg.list_pipelines()
    assert reg.get("dummy") is DummyFilterPipeline

    instance = reg.create("dummy")
    assert isinstance(instance, DummyFilterPipeline)

    # Register factory
    reg.register("dummy_factory", factory=lambda: DummyFilterPipeline())
    factory_instance = reg.create("dummy_factory")
    assert isinstance(factory_instance, DummyFilterPipeline)

    # Unregister
    reg.unregister("dummy")
    assert reg.get("dummy") is None
    assert "dummy" not in reg.list_pipelines()


def test_jsonlines_item_pipeline_write(temp_dir: str) -> None:
    """Verifies JsonLinesItemPipeline writes valid UTF-8 JSON lines."""

    async def _run() -> None:
        pipeline = JsonLinesItemPipeline(output_dir=temp_dir)
        spider = MockSimpleSpider()
        item = ScrapedItem(
            item_id="test_01",
            source_url="https://example.com/item1",
            title="テスト論文 (Japanese Title)",
            payload={"metric": 42, "status": "active"},
        )

        processed = await pipeline.process_item(item, spider)
        assert "jsonl_path" in processed.payload
        target_path = processed.payload["jsonl_path"]
        assert os.path.exists(target_path)
        assert target_path.endswith("mock_simple_spider.jsonl")

        with open(target_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        assert len(lines) == 1
        record = json.loads(lines[0])
        assert record["item_id"] == "test_01"
        assert record["title"] == "テスト論文 (Japanese Title)"
        assert record["payload"]["metric"] == 42

    asyncio.run(_run())


def test_jsonlines_item_pipeline_custom_file(temp_dir: str) -> None:
    """Verifies JsonLinesItemPipeline writing to an explicit output_file."""

    async def _run() -> None:
        custom_file = os.path.join(temp_dir, "custom_out", "custom.jsonl")
        pipeline = JsonLinesItemPipeline(output_file=custom_file)
        spider = MockSimpleSpider()
        item = ScrapedItem(
            item_id="custom_01",
            source_url="https://example.com/custom",
            title="Custom Out",
            payload={"data": [1, 2, 3]},
        )
        await pipeline.process_item(item, spider)
        assert os.path.exists(custom_file)

        with open(custom_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) == 1

    asyncio.run(_run())


def test_console_item_pipeline(caplog: Any) -> None:
    """Verifies ConsoleItemPipeline logging without exceptions."""

    async def _run() -> None:
        pipeline = ConsoleItemPipeline(log_level=logging.INFO)
        spider = MockSimpleSpider()
        item = ScrapedItem(
            item_id="log_01",
            source_url="https://example.com/log",
            title="Logging Test Item",
            payload={"flag": True},
        )
        with caplog.at_level(logging.INFO):
            res = await pipeline.process_item(item, spider)
        assert res.item_id == "log_01"

    asyncio.run(_run())


def test_engine_drop_item_and_pipeline_lifecycle() -> None:
    """Verifies Engine respects open_spider/close_spider and DropItem drops items."""

    async def _run() -> None:
        spider = MockSimpleSpider()
        pipeline = DummyFilterPipeline()
        engine = Engine()

        class MockDownloader:
            async def download(self, request: Request) -> Response:
                return Response(
                    url=request.url,
                    status_code=200,
                    headers={"content-type": "text/html"},
                    body=b"<html>OK</html>",
                    request=request,
                )

            async def close(self) -> None:
                pass

        engine.downloader = MockDownloader()  # type: ignore[assignment]
        crawled = await engine.crawl(
            spider=spider,
            pipelines=[pipeline],
            middlewares=[],
        )

        assert pipeline.opened is True
        assert pipeline.closed is True
        # item_1 is kept, item_2 had 'DROP' and was dropped
        assert len(crawled) == 1
        assert crawled[0].item_id == "item_1"
        assert crawled[0].payload.get("processed_by_dummy") is True

    asyncio.run(_run())


def test_runner_dependency_injection(temp_dir: str) -> None:
    """Verifies run_spider accepts injected pipelines."""

    async def _run() -> None:
        custom_pipe = DummyFilterPipeline()
        from spider.registry import get_spider_registry

        get_spider_registry().register("mock_simple", spider_cls=MockSimpleSpider)

        class MockDownloader:
            async def download(self, request: Request) -> Response:
                return Response(
                    url=request.url,
                    status_code=200,
                    headers={"content-type": "text/html"},
                    body=b"<html>OK</html>",
                    request=request,
                )

            async def close(self) -> None:
                pass

        with pytest.MonkeyPatch.context() as mp:
            mp.setattr(
                "spider.runner.AsyncHttpDownloader",
                lambda: MockDownloader(),
            )
            items = await run_spider(
                spider_name="mock_simple",
                pipelines=[custom_pipe],
                max_requests=1,
            )
            assert len(items) == 1
            assert items[0].payload.get("processed_by_dummy") is True
            assert custom_pipe.opened is True
            assert custom_pipe.closed is True

    asyncio.run(_run())
