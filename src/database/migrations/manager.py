#!/usr/bin/env python3
"""
MigrationManager orchestrator for database schema lifecycle management.
Orchestrates create, up, down, and status operations across Primary (src/database)
and Secondary (sqlite3) backends.
Conforms to DSN-30 Section 6 specification.
"""

import datetime
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .connection import DatabaseAdapter, get_adapter
from .inspector import SchemaInspector
from .models import (
    MIGRATION_FILENAME_PATTERN,
    BackendType,
    MigrationDirection,
    MigrationFile,
    MigrationFileNotFoundError,
    MigrationRecord,
    MigrationStatus,
    parse_migration_filename,
    validate_migration_name,
)
from .runner import MigrationRunner


def _extract_seq_num(entry: Path) -> int:
    if not entry.is_file() or not entry.name.endswith(".sql"):
        return 0
    m = re.match(r"^(\d{4})_", entry.name)
    return int(m.group(1)) if m else 0


def _compute_next_sequence_prefix(migrations_dir: Path) -> str:
    """Computes the next 4-digit zero-padded sequential prefix (e.g. '0001')."""
    if not migrations_dir.exists():
        return "0001"
    seqs = [_extract_seq_num(e) for e in migrations_dir.iterdir()]
    max_seq = max(seqs) if seqs else 0
    return f"{max_seq + 1:04d}"


class MigrationManager:
    """
    Core orchestrator coordinating database migrations.
    Encapsulates business logic for schema creation, application, rollback,
    and status reporting with zero third-party dependencies.
    """

    def __init__(
        self,
        db_path: Path | str,
        migrations_dir: Optional[Path | str] = None,
        backend: BackendType | str = BackendType.PYDB,
        adapter: Optional[DatabaseAdapter] = None,
    ) -> None:
        self.backend = (
            BackendType.from_str(backend) if isinstance(backend, str) else backend
        )
        self.db_path = Path(db_path)

        if migrations_dir is not None:
            self.migrations_dir = Path(migrations_dir).resolve()
        else:
            self.migrations_dir = (
                Path(__file__).resolve().parent.parent.parent.parent / "migrations"
            ).resolve()

        self.migrations_dir.mkdir(parents=True, exist_ok=True)
        self.adapter = (
            adapter
            if adapter is not None
            else get_adapter(backend=self.backend, db_path=self.db_path)
        )
        self.runner = MigrationRunner(adapter=self.adapter)

    def create(self, name: str) -> Tuple[Path, Path]:
        """
        Generates a new pair of sequential .up.sql and .down.sql skeleton files (e.g. 0001_name.up.sql).
        Validates name to avoid path traversal and shell injection.
        """
        clean_name = validate_migration_name(name)
        now = datetime.datetime.now(datetime.timezone.utc)
        seq = _compute_next_sequence_prefix(self.migrations_dir)

        up_filename = f"{seq}_{clean_name}.up.sql"
        down_filename = f"{seq}_{clean_name}.down.sql"

        up_path = self.migrations_dir / up_filename
        down_path = self.migrations_dir / down_filename

        up_header = (
            f"-- Migration: {clean_name} (UP)\n"
            f"-- Version:   {seq}\n"
            f"-- Backend:   Compatible with Primary (src.database) and Secondary (sqlite3)\n"
            f"-- Created:   {now.isoformat()}\n\n"
        )
        down_header = (
            f"-- Migration: {clean_name} (DOWN)\n"
            f"-- Version:   {seq}\n"
            f"-- Backend:   Compatible with Primary (src.database) and Secondary (sqlite3)\n"
            f"-- Created:   {now.isoformat()}\n\n"
        )

        up_path.write_text(up_header, encoding="utf-8")
        down_path.write_text(down_header, encoding="utf-8")
        return up_path, down_path

    def _parse_entry_if_matching(
        self, entry: Path, direction: str
    ) -> Optional[MigrationFile]:
        if not entry.is_file() or not MIGRATION_FILENAME_PATTERN.match(entry.name):
            return None
        mf = parse_migration_filename(entry, base_dir=self.migrations_dir)
        return mf if mf.direction == direction else None

    def get_migration_files(self, direction: str = "up") -> List[MigrationFile]:
        """
        Scans the migrations directory and returns sorted migration files for the given direction.
        """
        if direction not in (
            MigrationDirection.UP.value,
            MigrationDirection.DOWN.value,
        ):
            raise ValueError(
                f"Invalid direction '{direction}'. Must be 'up' or 'down'."
            )

        if not self.migrations_dir.exists():
            return []

        files: List[MigrationFile] = []
        for entry in sorted(self.migrations_dir.iterdir(), key=lambda p: p.name):
            mf = self._parse_entry_if_matching(entry, direction)
            if mf is not None:
                files.append(mf)

        files.sort(key=lambda m: m.version)
        return files

    @staticmethod
    def _format_file_status(
        m: MigrationFile, rec: Optional[MigrationRecord]
    ) -> Dict[str, Any]:
        is_applied = rec is not None
        return {
            "version": m.version,
            "name": m.name,
            "status": (
                MigrationStatus.APPLIED.value
                if is_applied
                else MigrationStatus.PENDING.value
            ),
            "applied_at": rec.applied_at if rec else "-",
            "execution_time_ms": rec.execution_time_ms if rec else None,
        }

    @staticmethod
    def _format_untracked_status(rec: MigrationRecord) -> Dict[str, Any]:
        return {
            "version": rec.version,
            "name": rec.name,
            "status": MigrationStatus.APPLIED.value,
            "applied_at": rec.applied_at,
            "execution_time_ms": rec.execution_time_ms,
        }

    def status(self) -> List[Dict[str, Any]]:
        """
        Retrieves the migration status of all known files and records.
        Returns structured list with version, name, status, and applied metadata.
        """
        applied_records = SchemaInspector.get_applied_migrations(self.adapter)
        applied_map = {r.version: r for r in applied_records}
        up_files = self.get_migration_files(direction="up")

        records: List[Dict[str, Any]] = []
        seen_versions = set()

        for m in up_files:
            seen_versions.add(m.version)
            records.append(self._format_file_status(m, applied_map.get(m.version)))

        for rec in applied_records:
            if rec.version not in seen_versions:
                records.append(self._format_untracked_status(rec))

        records.sort(key=lambda r: str(r["version"]))
        return records

    @staticmethod
    def _slice_pending(
        pending: List[MigrationFile], steps: Optional[int]
    ) -> List[MigrationFile]:
        if steps is not None and steps > 0:
            return pending[:steps]
        return pending

    def _get_pending_migrations(
        self, steps: Optional[int] = None
    ) -> List[MigrationFile]:
        applied_records = SchemaInspector.get_applied_migrations(self.adapter)
        applied_versions = {r.version for r in applied_records}
        up_files = self.get_migration_files(direction="up")
        pending = [m for m in up_files if m.version not in applied_versions]
        return self._slice_pending(pending, steps)

    def up(self, steps: Optional[int] = None) -> List[MigrationRecord]:
        """
        Applies pending migrations in ascending version order.
        Limits execution count if steps parameter is provided.
        """
        pending = self._get_pending_migrations(steps)
        if not pending:
            return []

        applied: List[MigrationRecord] = []
        for migration in pending:
            rec = self.runner.apply(migration)
            applied.append(rec)

        return applied

    def down(self, steps: int = 1) -> List[str]:
        """
        Rolls back the latest applied migrations in descending version order.
        Raises MigrationFileNotFoundError if corresponding .down.sql is missing.
        """
        if steps <= 0:
            return []

        applied_records = SchemaInspector.get_applied_migrations(self.adapter)
        if not applied_records:
            return []

        to_rollback = list(reversed(applied_records))[:steps]
        rolled_back: List[str] = []

        for rec in to_rollback:
            down_filename = f"{rec.version}_{rec.name}.down.sql"
            down_path = self.migrations_dir / down_filename
            if not down_path.exists():
                raise MigrationFileNotFoundError(
                    f"Required rollback file not found: {down_path}"
                )

            down_file = parse_migration_filename(
                down_path, base_dir=self.migrations_dir
            )
            self.runner.rollback(down_file)
            rolled_back.append(rec.version)

        return rolled_back

    def close(self) -> None:
        """Closes the underlying database adapter connection."""
        self.adapter.close()

    def __enter__(self) -> "MigrationManager":
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.close()
