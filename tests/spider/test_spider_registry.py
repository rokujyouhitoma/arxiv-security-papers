"""
Unit tests for Spider Registry and Spider SPI plugin architecture.
"""

from typing import AsyncIterator, Union

from spider.core.downloader import Request, Response
from spider.core.engine import ScrapedItem
from spider.registry import SpiderRegistry, get_spider_registry
from spider.spiders.base import BaseSpider


class DummyTestSpider(BaseSpider):
    name = "dummy_test_spider"

    async def parse(
        self, response: Response
    ) -> AsyncIterator[Union[Request, ScrapedItem]]:
        yield ScrapedItem(url="http://example.com")


def test_spider_registry_operations():
    registry = SpiderRegistry()
    assert len(registry.list_spiders()) == 0

    # Register class
    registry.register("dummy", spider_cls=DummyTestSpider)
    assert registry.get("dummy") == DummyTestSpider
    assert registry.list_spiders() == ["dummy"]

    # Instantiate
    instance = registry.create("dummy")
    assert isinstance(instance, DummyTestSpider)
    assert instance.name == "dummy_test_spider"

    # Register factory
    def spider_factory():
        return DummyTestSpider()

    registry.register("dummy_factory", factory=spider_factory)
    inst2 = registry.create("dummy_factory")
    assert isinstance(inst2, DummyTestSpider)

    # Unregister
    registry.unregister("dummy")
    assert registry.get("dummy") is None
    assert "dummy" not in registry.list_spiders()


def test_global_spider_registry():
    reg = get_spider_registry()
    assert isinstance(reg, SpiderRegistry)
