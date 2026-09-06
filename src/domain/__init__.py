"""
Domain Layer for Specialized Intelligence Applications.
Provides decoupled domain plugins (Security Papers, Cryptography, AI Safety, etc.)
over the reusable infrastructure platforms (DB, Search, Spider, Graph, Workflow, Supervisor).
"""

from .registry import BaseDomainPlugin, DomainRegistry, get_domain_registry
from .security import SecurityPapersDomainPlugin, create_security_plugin
from .source_resolver import resolve_paper_source_info

# Automatically register built-in security domain plugin
get_domain_registry().register(create_security_plugin())

__all__ = [
    "BaseDomainPlugin",
    "DomainRegistry",
    "get_domain_registry",
    "SecurityPapersDomainPlugin",
    "create_security_plugin",
    "resolve_paper_source_info",
]
