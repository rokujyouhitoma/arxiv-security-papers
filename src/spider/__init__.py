"""Spider framework core package."""

from typing import Any

from .core.bloom import BloomFilter, ScalableBloomFilter
from .core.downloader import AsyncHttpDownloader, Request, Response
from .core.engine import Engine, ScrapedItem
from .core.scheduler import Scheduler
from .core.selector import DOMNode, PureDOMParser, Selector, XmlNode, XmlSelector
from .distributed.consistent_hash import ConsistentHashRouter
from .distributed.contracts import SpiderContractVerifier
from .distributed.state_storage import StateStorage
from .downloader.middleware import (
    HttpCacheMiddleware,
    RobotsTxtMiddleware,
    UserAgentMiddleware,
)
from .downloader.spa_handler import SpaContentExtractor
from .dsl import FunctionalSpider, SpiderBuilder, scrape, spider
from .pipeline.base import (
    BaseItemPipeline,
    ConsoleItemPipeline,
    DropItem,
    JsonLinesItemPipeline,
    PipelineRegistry,
    get_pipeline_registry,
)
from .policies.autothrottle import AutoThrottlePolicy
from .policies.normalizer import TrapDetector, UrlNormalizer
from .policies.opic import OpicCalculator, TopicRelevanceScorer
from .registry import SpiderRegistry, get_spider_registry
from .spiders.base import BaseSpider

__all__ = [
    "Engine",
    "Request",
    "Response",
    "Scheduler",
    "ScrapedItem",
    "AsyncHttpDownloader",
    "DOMNode",
    "PureDOMParser",
    "Selector",
    "XmlNode",
    "XmlSelector",
    "BloomFilter",
    "ScalableBloomFilter",
    "UserAgentMiddleware",
    "RobotsTxtMiddleware",
    "HttpCacheMiddleware",
    "SpaContentExtractor",
    "AutoThrottlePolicy",
    "UrlNormalizer",
    "TrapDetector",
    "OpicCalculator",
    "TopicRelevanceScorer",
    "SpiderRegistry",
    "get_spider_registry",
    "BaseSpider",
    "BaseItemPipeline",
    "JsonLinesItemPipeline",
    "ConsoleItemPipeline",
    "DropItem",
    "PipelineRegistry",
    "get_pipeline_registry",
    "ConsistentHashRouter",
    "StateStorage",
    "SpiderContractVerifier",
    "SpiderBuilder",
    "FunctionalSpider",
    "spider",
    "scrape",
    "CrawlJob",
    "CrawlResult",
    "SpiderDaemonWorker",
    "SpiderDaemonClient",
]

from .daemon import (  # noqa: E402
    CrawlJob,
    CrawlResult,
    SpiderDaemonClient,
    SpiderDaemonWorker,
)

_LEGACY_EXPORTS = {
    "OkfItemPipeline": "domain.security.pipeline.okf_pipeline",
    "ArxivSpider": "domain.security.spiders.arxiv_spider",
    "IacrSpider": "domain.security.spiders.iacr_spider",
    "AdvisorySpider": "domain.security.spiders.advisory_spider",
}


def __getattr__(name: str) -> Any:
    if name in _LEGACY_EXPORTS:
        import importlib

        mod_name = _LEGACY_EXPORTS[name]
        mod = importlib.import_module(mod_name)
        return getattr(mod, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
