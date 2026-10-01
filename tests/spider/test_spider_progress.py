"""Unit tests for spider crawl progress calculation and telemetry persistence."""

import time
from typing import Any, List

import pytest

from spider.core.downloader import Request
from spider.core.engine import Engine, ScrapedItem
from spider.core.scheduler import Scheduler
from spider.distributed.state_storage import StateStorage
from spider.spiders.base import BaseSpider


class DummyProgressSpider(BaseSpider):
    name = "dummy_progress"
    start_urls = ["https://example.com/1", "https://example.com/2"]

    def parse(self, response: Any) -> List[Any]:
        return [
            ScrapedItem(
                item_id="item-1",
                source_url=response.url,
                title="Test Item",
                payload={"data": 123},
            )
        ]


def test_calculate_progress_zero() -> None:
    res = StateStorage.calculate_progress(0, 0, 0.0)
    assert res["processed"] == 0
    assert res["pending"] == 0
    assert res["total"] == 0
    assert res["ratio_pct"] == 0.0
    assert res["pages_per_second"] == 0.0
    assert res["eta_seconds"] == 0.0


def test_calculate_progress_metrics() -> None:
    # 25 processed, 75 pending => total 100 => 25.0%
    # 10.0 seconds => 2.5 pages/s => ETA 75 / 2.5 = 30.0s
    res = StateStorage.calculate_progress(25, 75, 10.0)
    assert res["processed"] == 25
    assert res["pending"] == 75
    assert res["total"] == 100
    assert res["ratio_pct"] == 25.0
    assert res["pages_per_second"] == 2.5
    assert res["eta_seconds"] == 30.0
    assert res["elapsed_seconds"] == 10.0


def test_save_and_get_progress_telemetry(tmp_path: Any) -> None:
    progress_dir = str(tmp_path / "progress")
    start_time = time.time() - 5.0
    data = StateStorage.save_progress(
        spider_name="arxiv",
        processed=10,
        pending=30,
        start_time=start_time,
        status="RUNNING",
        base_dir=progress_dir,
    )
    assert data["spider_name"] == "arxiv"
    assert data["status"] == "RUNNING"
    assert data["is_active"] is True
    assert data["ratio_pct"] == 25.0

    retrieved = StateStorage.get_progress_info("arxiv", base_dir=progress_dir)
    assert retrieved["spider_name"] == "arxiv"
    assert retrieved["is_active"] is True
    assert retrieved["processed"] == 10
    assert retrieved["pending"] == 30

    cleared = StateStorage.clear_progress("arxiv", base_dir=progress_dir)
    assert cleared is True
    empty_info = StateStorage.get_progress_info("arxiv", base_dir=progress_dir)
    assert empty_info["is_active"] is False


@pytest.mark.anyio
async def test_engine_crawl_reports_progress(tmp_path: Any, monkeypatch: Any) -> None:
    progress_dir = str(tmp_path / "progress")
    orig_save = StateStorage.save_progress
    monkeypatch.setattr(
        StateStorage,
        "save_progress",
        lambda spider_name, processed, pending, start_time, status="RUNNING", base_dir=None: orig_save(
            spider_name,
            processed,
            pending,
            start_time,
            status,
            base_dir=progress_dir,
        ),
    )

    spider = DummyProgressSpider()
    scheduler = Scheduler()
    engine = Engine(scheduler=scheduler)

    from spider.core.downloader import Response

    # Run crawl with mocked downloader response
    class MockDownloader:
        async def download(self, req: Request) -> Response:
            return Response(
                url=req.url,
                status_code=200,
                headers={},
                body=b"<html>ok</html>",
                request=req,
            )

    engine.downloader = MockDownloader()  # type: ignore[assignment]
    items = await engine.crawl(spider=spider)
    assert len(items) == 2

    # After crawl completion, progress file exists and status is COMPLETED
    info = StateStorage.get_progress_info("dummy_progress", base_dir=progress_dir)
    assert info["status"] == "COMPLETED"
    assert info["processed"] == 2
