#!/usr/bin/env python3
"""
Pluggable Source Adapters Package.
"""

from .arxiv_adapter import ArxivSourceAdapter
from .base import BaseSourceAdapter, RawItem
from .feed_adapter import FeedSourceAdapter
from .iacr_adapter import IacrEprintSourceAdapter
from .registry import SourceRegistry, get_source_registry

__all__ = [
    "BaseSourceAdapter",
    "RawItem",
    "ArxivSourceAdapter",
    "IacrEprintSourceAdapter",
    "FeedSourceAdapter",
    "SourceRegistry",
    "get_source_registry",
]
