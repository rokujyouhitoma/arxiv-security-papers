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

    def __init__(self, auto_discover: bool = False) -> None:
        self._spiders: Dict[str, Type[BaseSpider]] = {}
        self._factories: Dict[str, Callable[..., BaseSpider]] = {}
        self._auto_discover = auto_discover

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
        res = self._spiders.get(name)
        if res is None and self._auto_discover:
            _auto_register_domain_spiders(self)
            res = self._spiders.get(name)
        return res

    def _ensure_discovered(self, name: str) -> None:
        if not self._auto_discover:
            return
        if name not in self._spiders and name not in self._factories:
            _auto_register_domain_spiders(self)

    def create(
        self, name: str, *args: object, **kwargs: object
    ) -> Optional[BaseSpider]:
        """Instantiates a registered spider by name."""
        self._ensure_discovered(name)
        if name in self._factories:
            return self._factories[name](*args, **kwargs)
        spider_cls = self._spiders.get(name)
        if spider_cls is not None:
            return spider_cls(*args, **kwargs)
        return None

    def list_spiders(self) -> List[str]:
        """Lists all registered spider names."""
        if self._auto_discover:
            _auto_register_domain_spiders(self)
        names = set(self._spiders.keys()) | set(self._factories.keys())
        return sorted(list(names))

    def unregister(self, name: str) -> None:
        """Removes a spider registration."""
        self._spiders.pop(name, None)
        self._factories.pop(name, None)


DiscoveryHook = Callable[[SpiderRegistry], None]
_DISCOVERY_HOOKS: List[DiscoveryHook] = []


def register_spider_discovery_hook(hook: DiscoveryHook) -> None:
    """Registers an external SPI discovery hook to be called during spider resolution."""
    if hook not in _DISCOVERY_HOOKS:
        _DISCOVERY_HOOKS.append(hook)


def _register_plugin_spiders(registry: SpiderRegistry, plugin: object) -> None:
    getter = getattr(plugin, "get_spiders", None)
    if not callable(getter):
        return
    spiders: Dict[str, Type[BaseSpider]] = getter()
    for name, spider_cls in spiders.items():
        if name not in registry._spiders and name not in registry._factories:
            registry.register(name, spider_cls=spider_cls)


def _auto_register_domain_spiders(registry: SpiderRegistry) -> None:
    """Discovers and registers spiders via registered hooks and domain plugins via SPI."""
    for hook in list(_DISCOVERY_HOOKS):
        try:
            hook(registry)
        except Exception as exc:
            logger.debug("Discovery hook %s failed: %s", hook, exc)

    try:
        from domain import get_domain_registry

        for plugin in get_domain_registry().get_all():
            _register_plugin_spiders(registry, plugin)
    except Exception as exc:
        logger.debug("Domain plugin spider auto-registration deferred: %s", exc)


_GLOBAL_SPIDER_REGISTRY = SpiderRegistry(auto_discover=True)


def get_spider_registry() -> SpiderRegistry:
    """Returns the global SpiderRegistry singleton."""
    return _GLOBAL_SPIDER_REGISTRY
