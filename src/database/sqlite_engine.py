#!/usr/bin/env python3
"""Backward-compatibility shim for database.compat.sqlite_engine."""

from .compat.sqlite_engine import (
    get_sqlite_connection,
    register_vector_functions,
    sync_from_vector_storage,
    sync_to_vector_storage,
)

__all__ = [
    "get_sqlite_connection",
    "register_vector_functions",
    "sync_from_vector_storage",
    "sync_to_vector_storage",
]
