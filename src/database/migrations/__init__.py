#!/usr/bin/env python3
"""
Database Migration Subsystem for arxiv-security-papers.
Provides zero-dependency raw SQL migrations for Primary (src/database Pure Python RDBMS)
and Secondary (sqlite3) database backends.
Conforms to DSN-30 specification.
"""

from .connection import DatabaseAdapter, PyDBAdapter, SQLiteAdapter, get_adapter
from .inspector import SchemaInspector
from .models import (
    BackendType,
    MigrationDirection,
    MigrationFile,
    MigrationRecord,
    MigrationStatus,
    parse_migration_filename,
    validate_migration_name,
)

__all__ = [
    "BackendType",
    "DatabaseAdapter",
    "MigrationDirection",
    "MigrationFile",
    "MigrationRecord",
    "MigrationStatus",
    "PyDBAdapter",
    "SQLiteAdapter",
    "SchemaInspector",
    "get_adapter",
    "parse_migration_filename",
    "validate_migration_name",
]
