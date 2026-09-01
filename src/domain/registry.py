#!/usr/bin/env python3
"""
Domain Registry and Plugin Architecture (SPI).
Provides lifecycle management, discovery, and decoupling for specialized domains.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class BaseDomainPlugin(ABC):
    """
    Abstract base class for domain plugins.
    Encapsulates domain-specific models, ontology, spiders, and transformers.
    """

    @property
    @abstractmethod
    def domain_id(self) -> str:
        """Unique identifier for the domain (e.g. 'security', 'crypto', 'ai_safety')."""
        pass

    @property
    @abstractmethod
    def display_name(self) -> str:
        """Human-readable display name for the domain."""
        pass

    @property
    def description(self) -> str:
        """Brief summary of the domain scope."""
        return ""

    def get_supported_categories(self) -> List[str]:
        """Returns arXiv or external category tags supported by this domain."""
        return []

    def get_spiders(self) -> Dict[str, Any]:
        """Returns mapping of spider names to spider classes or factories."""
        return {}

    def get_ontology_schema(self) -> Optional[Any]:
        """Returns domain ontology schema if available."""
        return None

    def initialize(self, workspace_dir: str) -> None:
        """Initializes domain resources, caches, or directories."""
        pass


class DomainRegistry:
    """
    Central registry for managing domain plugins.
    Allows dynamic registration and isolation of specialized domains.
    """

    def __init__(self) -> None:
        self._plugins: Dict[str, BaseDomainPlugin] = {}

    def register(self, plugin: BaseDomainPlugin) -> None:
        """Registers a domain plugin."""
        self._plugins[plugin.domain_id] = plugin
        logger.debug(
            "Registered domain plugin: %s (%s)", plugin.domain_id, plugin.display_name
        )

    def get(self, domain_id: str) -> Optional[BaseDomainPlugin]:
        """Retrieves a registered domain plugin by ID."""
        return self._plugins.get(domain_id)

    def list_domains(self) -> List[str]:
        """Lists all registered domain IDs."""
        return sorted(list(self._plugins.keys()))

    def get_all(self) -> List[BaseDomainPlugin]:
        """Returns all registered domain plugin instances."""
        return list(self._plugins.values())

    def unregister(self, domain_id: str) -> None:
        """Removes a domain plugin registration."""
        self._plugins.pop(domain_id, None)


_GLOBAL_DOMAIN_REGISTRY = DomainRegistry()


def get_domain_registry() -> DomainRegistry:
    """Returns the global DomainRegistry singleton."""
    return _GLOBAL_DOMAIN_REGISTRY
