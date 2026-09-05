#!/usr/bin/env python3
"""Backward-compatibility shim for domain.security.cti.registry."""

from domain.security.cti.registry import BUILTIN_FALLBACK_TECHNIQUES, MITRECTIRegistry

__all__ = [
    "BUILTIN_FALLBACK_TECHNIQUES",
    "MITRECTIRegistry",
]
