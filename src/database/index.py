#!/usr/bin/env python3
"""Backward-compatibility shim for database.index.index."""

from .index.index import HNSWIndex

__all__ = ["HNSWIndex"]
