#!/usr/bin/env python3
"""
Atomic transaction runner for database schema migrations.
Executes raw SQL migration scripts within atomic transaction boundaries.
Supports Primary (src/database Pure Python RDBMS) and Secondary (sqlite3).
Conforms to DSN-30 Section 6 specification.
"""

import datetime
import hashlib
import time
from typing import Any, List, Set

from .connection import DatabaseAdapter
from .inspector import SchemaInspector
from .models import (
    BackendType,
    MigrationExecutionError,
    MigrationFile,
    MigrationFileNotFoundError,
    MigrationRecord,
)


class MigrationRunner:
    """
    Atomic transaction runner executing .up.sql and .down.sql scripts.
    Guarantees all-or-nothing execution, ARIES WAL / SQLite WAL sync,
    and automatic full rollback on failure.
    """

    def __init__(self, adapter: DatabaseAdapter) -> None:
        self.adapter = adapter

    @staticmethod
    def split_sql_statements(sql: str) -> List[str]:
        """
        Splits a raw SQL script into individual executable statements.
        Filters out SQL comments (-- ...) and empty chunks.
        """
        cleaned_lines: List[str] = []
        for line in sql.splitlines():
            stripped = line.strip()
            if stripped.startswith("--"):
                continue
            cleaned_lines.append(line)
        cleaned_sql = "\n".join(cleaned_lines)

        statements: List[str] = []
        for part in cleaned_sql.split(";"):
            stmt = part.strip()
            if stmt:
                statements.append(stmt)
        return statements

    @staticmethod
    def compute_checksum(content: str) -> str:
        """Computes SHA-256 hex digest of the SQL content."""
        return hashlib.sha256(content.encode("utf-8")).hexdigest()

    def _get_table_names(self, conn: Any) -> List[str]:
        """Retrieves existing table names from the connection."""
        if hasattr(conn, "tables") and isinstance(conn.tables, list):
            return list(conn.tables)
        try:
            cur = conn.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
            rows = cur.fetchall()
            return [str(r[0]) for r in rows]
        except Exception:
            return []

    def _begin_transaction(self, conn: Any) -> None:
        """Starts a transaction on the connection if supported by the backend."""
        if self.adapter.backend_type == BackendType.SQLITE:
            conn.execute("BEGIN IMMEDIATE")

    @staticmethod
    def _drop_table_safely(cur: Any, tname: str) -> None:
        try:
            cur.execute(f"DROP TABLE IF EXISTS {tname}")
        except Exception:
            pass

    @staticmethod
    def _commit_safely(conn: Any) -> None:
        if hasattr(conn, "commit"):
            try:
                conn.commit()
            except Exception:
                pass

    def _cleanup_failed_tables(
        self, conn: Any, cur: Any, initial_tables: Set[str]
    ) -> None:
        """Drops any newly created tables if the transaction failed."""
        try:
            current_tables = set(self._get_table_names(conn))
            newly_created = current_tables - initial_tables
            for tname in newly_created:
                self._drop_table_safely(cur, tname)
            if newly_created:
                self._commit_safely(conn)
        except Exception:
            pass

    def apply(self, migration: MigrationFile) -> MigrationRecord:
        """
        Atomically applies an .up.sql migration file within a single transaction.
        Updates schema_migrations catalog upon success.
        On failure, rolls back all changes and raises MigrationExecutionError.
        """
        if not migration.filepath.exists():
            raise MigrationFileNotFoundError(
                f"Migration file not found: {migration.filepath}"
            )

        SchemaInspector.ensure_schema_migrations_table(self.adapter)
        content = migration.filepath.read_text(encoding="utf-8")
        checksum = self.compute_checksum(content)
        stmts = self.split_sql_statements(content)

        conn = self.adapter.connect()
        initial_tables = set(self._get_table_names(conn))
        start_time = time.perf_counter()

        self._begin_transaction(conn)
        cur = conn.cursor()
        try:
            for stmt in stmts:
                cur.execute(stmt)

            elapsed_ms = max(0, int(round((time.perf_counter() - start_time) * 1000)))
            applied_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            record = MigrationRecord(
                version=migration.version,
                name=migration.name,
                applied_at=applied_at,
                execution_time_ms=elapsed_ms,
                checksum=checksum,
            )

            insert_sql = (
                "INSERT INTO schema_migrations "
                "(version, name, applied_at, execution_time_ms, checksum) "
                "VALUES (?, ?, ?, ?, ?)"
            )
            cur.execute(
                insert_sql,
                (
                    record.version,
                    record.name,
                    record.applied_at,
                    record.execution_time_ms,
                    record.checksum,
                ),
            )
            conn.commit()
            return record

        except Exception as exc:
            try:
                conn.rollback()
            except Exception:
                pass
            self._cleanup_failed_tables(conn, cur, initial_tables)
            raise MigrationExecutionError(
                f"Failed to apply migration '{migration.identifier}' on "
                f"[{self.adapter.backend_type.value}]: {exc}"
            ) from exc

    def rollback(self, migration: MigrationFile) -> None:
        """
        Atomically rolls back a .down.sql migration file within a single transaction.
        Removes the migration record from schema_migrations catalog upon success.
        On failure, rolls back and raises MigrationExecutionError.
        """
        if not migration.filepath.exists():
            raise MigrationFileNotFoundError(
                f"Migration file not found: {migration.filepath}"
            )

        SchemaInspector.ensure_schema_migrations_table(self.adapter)
        content = migration.filepath.read_text(encoding="utf-8")
        stmts = self.split_sql_statements(content)

        conn = self.adapter.connect()
        self._begin_transaction(conn)
        cur = conn.cursor()
        try:
            for stmt in stmts:
                cur.execute(stmt)

            delete_sql = "DELETE FROM schema_migrations WHERE version = ?"
            cur.execute(delete_sql, (migration.version,))
            conn.commit()

        except Exception as exc:
            try:
                conn.rollback()
            except Exception:
                pass
            raise MigrationExecutionError(
                f"Failed to rollback migration '{migration.identifier}' on "
                f"[{self.adapter.backend_type.value}]: {exc}"
            ) from exc
