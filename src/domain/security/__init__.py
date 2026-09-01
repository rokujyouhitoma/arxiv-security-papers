"""
Security Domain Package.
Contains domain-specific implementations for Computer Security and Cryptography papers.
"""

from .plugin import SecurityPapersDomainPlugin, create_security_plugin

__all__ = [
    "SecurityPapersDomainPlugin",
    "create_security_plugin",
]
