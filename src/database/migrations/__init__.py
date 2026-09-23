#!/usr/bin/env python3
"""
Database Migration Subsystem for arxiv-security-papers.
Provides zero-dependency raw SQL migrations for Primary (src/database Pure Python RDBMS)
and Secondary (sqlite3) database backends.
Conforms to DSN-30 specification.
"""

from .cli import MigrationsCommand
from .connection import DatabaseAdapter, PyDBAdapter, SQLiteAdapter, get_adapter
from .inspector import SchemaInspector
from .manager import MigrationManager
from .models import (
    BackendType,
    MigrationDirection,
    MigrationError,
    MigrationExecutionError,
    MigrationFile,
    MigrationFileNotFoundError,
    MigrationRecord,
    MigrationStatus,
    parse_migration_filename,
    validate_migration_name,
)
from .runner import MigrationRunner

__all__ = [
    "BackendType",
    "DatabaseAdapter",
    "MigrationDirection",
    "MigrationError",
    "MigrationExecutionError",
    "MigrationFile",
    "MigrationFileNotFoundError",
    "MigrationManager",
    "MigrationRecord",
    "MigrationRunner",
    "MigrationStatus",
    "MigrationsCommand",
    "PyDBAdapter",
    "SQLiteAdapter",
    "SchemaInspector",
    "get_adapter",
    "parse_migration_filename",
    "validate_migration_name",
]
