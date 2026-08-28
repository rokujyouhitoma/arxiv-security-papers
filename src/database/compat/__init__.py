#!/usr/bin/env python3
"""Compatibility and Tooling Subpackage."""

from .profiler import DatabaseProfiler, ProfileResult
from .sqlite_bridge import attach_to_sqlite, cosine_similarity
from .sqlite_engine import (
    get_sqlite_connection,
    register_vector_functions,
    sync_from_vector_storage,
    sync_to_vector_storage,
)

__all__ = [
    "DatabaseProfiler",
    "ProfileResult",
    "attach_to_sqlite",
    "cosine_similarity",
    "get_sqlite_connection",
    "register_vector_functions",
    "sync_from_vector_storage",
    "sync_to_vector_storage",
]
