#!/usr/bin/env python3
"""Backward-compatibility shim for domain.security.taxonomy.stride."""

from domain.security.taxonomy.stride import (
    STRIDE_CATEGORIES_MAP,
    extract_stride_categories,
)

__all__ = [
    "STRIDE_CATEGORIES_MAP",
    "extract_stride_categories",
]
