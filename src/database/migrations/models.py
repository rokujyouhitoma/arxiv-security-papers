#!/usr/bin/env python3
"""
Data models, enums, and validation functions for database migration engine.
Conforms to DSN-30 specification.
"""

import re
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional

MIGRATION_FILENAME_PATTERN = re.compile(
    r"^(\d{4}_\d{14}|\d{14}|\d{4})_([a-z0-9_]+)\.(up|down)\.sql$"
)
MIGRATION_NAME_PATTERN = re.compile(r"^[a-z0-9_]+$")


class BackendType(str, Enum):
    """Supported database backends in order of project priority."""

    PYDB = "pydb"  # Primary Target: src/database (Pure Python RDBMS)
    SQLITE = "sqlite"  # Secondary Target: sqlite3 (Supported Backend)

    @classmethod
    def from_str(cls, val: str) -> "BackendType":
        normalized = val.strip().lower()
        if normalized in ("pydb", "pure_python", "custom"):
            return cls.PYDB
        if normalized in ("sqlite", "sqlite3"):
            return cls.SQLITE
        raise ValueError(
            f"Unsupported backend type '{val}'. Allowed options: 'pydb' (Primary), 'sqlite' (Secondary)."
        )


class MigrationStatus(str, Enum):
    """Migration application status."""

    APPLIED = "APPLIED"
    PENDING = "PENDING"


class MigrationDirection(str, Enum):
    """Migration direction."""

    UP = "up"
    DOWN = "down"


class MigrationError(Exception):
    """Base exception for all database migration related errors."""

    pass


class MigrationExecutionError(MigrationError):
    """Raised when SQL execution fails during migration application or rollback."""

    pass


class MigrationFileNotFoundError(MigrationError):
    """Raised when a required migration file (e.g. .down.sql) is not found."""

    pass


@dataclass(frozen=True)
class MigrationFile:
    """Represents a physical SQL migration file on disk."""

    version: str
    name: str
    direction: str
    filepath: Path

    @property
    def identifier(self) -> str:
        return f"{self.version}_{self.name}"

    @property
    def is_up(self) -> bool:
        return self.direction == MigrationDirection.UP.value

    @property
    def is_down(self) -> bool:
        return self.direction == MigrationDirection.DOWN.value


@dataclass(frozen=True)
class MigrationRecord:
    """Represents an applied migration stored in schema_migrations table."""

    version: str
    name: str
    applied_at: str
    execution_time_ms: int
    checksum: Optional[str] = None

    @property
    def identifier(self) -> str:
        return f"{self.version}_{self.name}"


def _check_name_security(cleaned: str) -> None:
    for char in ("/", "\\", ".."):
        if char in cleaned:
            raise ValueError(
                f"Invalid migration name '{cleaned}': path separators and traversal '..' are strictly prohibited."
            )


def validate_migration_name(name: str) -> str:
    """
    Validates a migration name to prevent path traversal and shell injection.
    Must consist only of lowercase alphanumeric characters and underscores.
    """
    cleaned = name.strip()
    if not cleaned:
        raise ValueError("Migration name cannot be empty.")
    _check_name_security(cleaned)
    if not MIGRATION_NAME_PATTERN.match(cleaned):
        raise ValueError(
            f"Invalid migration name '{cleaned}': must match pattern '^[a-z0-9_]+$'."
        )
    return cleaned


def _check_path_traversal(filepath: Path, base_dir: Optional[Path]) -> None:
    if ".." in filepath.parts:
        raise ValueError(f"Path traversal detected in migration path: {filepath}")
    if filepath.is_absolute() and base_dir is not None:
        if not str(filepath).startswith(str(base_dir)):
            raise ValueError(f"Path traversal detected in migration path: {filepath}")


def _resolve_migration_path(filepath: Path, base_dir: Optional[Path]) -> Path:
    if filepath.is_absolute() or base_dir is None:
        return filepath
    return base_dir / filepath.name


def parse_migration_filename(
    path_or_filename: str | Path,
    base_dir: Optional[Path] = None,
) -> MigrationFile:
    """
    Parses a migration file name into a MigrationFile object.
    Strictly verifies filename pattern YYYYMMDDHHMMSS_name.(up|down).sql.
    """
    filepath = Path(path_or_filename)
    match = MIGRATION_FILENAME_PATTERN.match(filepath.name)
    if not match:
        raise ValueError(
            f"Invalid migration filename '{filepath.name}'. "
            f"Must follow format: '<version>_<description>.(up|down).sql' "
            f"(e.g., '0001_baseline.up.sql' or '20260923000000_init_schema.up.sql')."
        )

    _check_path_traversal(filepath, base_dir)
    version, name, direction = match.groups()
    return MigrationFile(
        version=version,
        name=name,
        direction=direction,
        filepath=_resolve_migration_path(filepath, base_dir),
    )
