#!/usr/bin/env python3
"""Backward-compatibility shim for database.compat.sqlite_engine."""

from .compat.sqlite_engine import (
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
    "SQLiteConnection",
    "SQLiteCursor",
    "SQLiteRow",
    "count_sqlite_table_rows",
    "get_sqlite_connection",
    "get_sqlite_table_names",
    "register_vector_functions",
    "sum_sqlite_table_rows",
    "sync_from_vector_storage",
    "sync_to_vector_storage",
]
