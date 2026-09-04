#!/usr/bin/env python3
"""Compatibility and Tooling Subpackage."""

from .profiler import DatabaseProfiler, ProfileResult
from .sqlite_bridge import attach_to_sqlite, cosine_similarity
from .sqlite_engine import (
    SQLiteConnection,
    SQLiteCursor,
    SQLiteRow,
    count_sqlite_table_rows,
    get_sqlite_connection,
    get_sqlite_table_names,
    register_vector_functions,
    sum_sqlite_table_rows,
    sync_from_vector_storage,
    sync_to_vector_storage,
)

__all__ = [
    "DatabaseProfiler",
    "ProfileResult",
    "SQLiteConnection",
    "SQLiteCursor",
    "SQLiteRow",
    "attach_to_sqlite",
    "cosine_similarity",
    "count_sqlite_table_rows",
    "get_sqlite_connection",
    "get_sqlite_table_names",
    "register_vector_functions",
    "sum_sqlite_table_rows",
    "sync_from_vector_storage",
    "sync_to_vector_storage",
]
