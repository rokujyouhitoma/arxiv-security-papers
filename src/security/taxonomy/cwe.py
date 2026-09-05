#!/usr/bin/env python3
"""Backward-compatibility shim for domain.security.taxonomy.cwe."""

from domain.security.taxonomy.cwe import CWE_DEFENSE_MAP, get_cwe_recipe

__all__ = [
    "CWE_DEFENSE_MAP",
    "get_cwe_recipe",
]
