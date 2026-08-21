from .core.bloom import BloomFilter, ScalableBloomFilter
from .core.downloader import AsyncHttpDownloader, Request, Response
from .core.engine import Engine, ScrapedItem
from .core.scheduler import Scheduler
from .core.selector import DOMNode, PureDOMParser, Selector
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
from .pipeline.okf_pipeline import OkfItemPipeline
from .policies.autothrottle import AutoThrottlePolicy
from .policies.normalizer import TrapDetector, UrlNormalizer
from .policies.opic import OpicCalculator, TopicRelevanceScorer
from .spiders.advisory_spider import AdvisorySpider
from .spiders.arxiv_spider import ArxivSpider
from .spiders.base import BaseSpider
from .spiders.iacr_spider import IacrSpider

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
    "BaseSpider",
    "ArxivSpider",
    "IacrSpider",
    "AdvisorySpider",
    "OkfItemPipeline",
    "ConsistentHashRouter",
    "StateStorage",
    "SpiderContractVerifier",
    "SpiderBuilder",
    "FunctionalSpider",
    "spider",
    "scrape",
]
