#!/usr/bin/env python3
"""
Spider Registry and SPI (Service Provider Interface) for Extensible Crawlers.
Provides plugin registration, discovery, and instantiation for domain-specific spiders.
"""

from __future__ import annotations

import logging
from typing import Callable, Dict, List, Optional, Type

from .spiders.base import BaseSpider

logger = logging.getLogger(__name__)


class SpiderRegistry:
    """
    Central registry for spider implementations.
    Allows domains to register custom spiders without modifying infrastructure code.
    """

    def __init__(self) -> None:
        self._spiders: Dict[str, Type[BaseSpider]] = {}
        self._factories: Dict[str, Callable[..., BaseSpider]] = {}

    def register(
        self,
        name: str,
        spider_cls: Optional[Type[BaseSpider]] = None,
        factory: Optional[Callable[..., BaseSpider]] = None,
    ) -> None:
        """Registers a spider class or factory under a given name."""
        if spider_cls is not None:
            self._spiders[name] = spider_cls
        if factory is not None:
            self._factories[name] = factory
        logger.debug("Registered spider: %s", name)

    def get(self, name: str) -> Optional[Type[BaseSpider]]:
        """Retrieves a registered spider class by name."""
        return self._spiders.get(name)

    def create(
        self, name: str, *args: object, **kwargs: object
    ) -> Optional[BaseSpider]:
        """Instantiates a registered spider by name."""
        if name in self._factories:
            return self._factories[name](*args, **kwargs)
        spider_cls = self._spiders.get(name)
        if spider_cls is not None:
            return spider_cls(*args, **kwargs)
        return None

    def list_spiders(self) -> List[str]:
        """Lists all registered spider names."""
        names = set(self._spiders.keys()) | set(self._factories.keys())
        return sorted(list(names))

    def unregister(self, name: str) -> None:
        """Removes a spider registration."""
        self._spiders.pop(name, None)
        self._factories.pop(name, None)


_GLOBAL_SPIDER_REGISTRY = SpiderRegistry()


def get_spider_registry() -> SpiderRegistry:
    """Returns the global SpiderRegistry singleton."""
    return _GLOBAL_SPIDER_REGISTRY
