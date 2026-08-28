#!/usr/bin/env python3
"""Backward-compatibility shim for database.compat.sqlite_bridge."""

from .compat.sqlite_bridge import attach_to_sqlite, cosine_similarity

__all__ = ["attach_to_sqlite", "cosine_similarity"]
