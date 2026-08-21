#!/usr/bin/env python3
"""
Source Adapter Registry.
Provides dynamic registration and lookup of pluggable source adapters.
"""

from typing import Dict, List, Optional

from .arxiv_adapter import ArxivSourceAdapter
from .base import BaseSourceAdapter
from .feed_adapter import FeedSourceAdapter
from .iacr_adapter import IacrEprintSourceAdapter
from .spider_adapter import SpiderSourceAdapter


class SourceRegistry:
    """Registry managing available data source adapters."""

    def __init__(self) -> None:
        self._adapters: Dict[str, BaseSourceAdapter] = {}
        self._register_defaults()

    def _register_defaults(self) -> None:
        """Registers default built-in source adapters."""
        self.register(ArxivSourceAdapter())
        self.register(IacrEprintSourceAdapter())
        self.register(FeedSourceAdapter())
        self.register(SpiderSourceAdapter(name="spider_arxiv", spider_name="arxiv"))
        self.register(SpiderSourceAdapter(name="spider_iacr", spider_name="iacr"))
        self.register(
            SpiderSourceAdapter(name="spider_advisory", spider_name="advisory")
        )

    def register(self, adapter: BaseSourceAdapter) -> None:
        """Registers a source adapter instance."""
        self._adapters[adapter.source_name] = adapter

    def get(self, source_name: str) -> Optional[BaseSourceAdapter]:
        """Retrieves an adapter by its source name."""
        return self._adapters.get(source_name)

    def list_sources(self) -> List[str]:
        """Lists all registered source adapter names."""
        return sorted(list(self._adapters.keys()))


# Default global registry singleton
_GLOBAL_REGISTRY: Optional[SourceRegistry] = None


def get_source_registry() -> SourceRegistry:
    """Returns the global SourceRegistry singleton instance."""
    global _GLOBAL_REGISTRY
    if _GLOBAL_REGISTRY is None:
        _GLOBAL_REGISTRY = SourceRegistry()
    return _GLOBAL_REGISTRY
