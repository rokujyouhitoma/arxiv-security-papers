#!/usr/bin/env python3
"""
Schema inspector and metadata catalog manager for schema_migrations table.
Conforms to DSN-30 Section 3 specification.
"""

from typing import List

from .connection import DatabaseAdapter
from .models import MigrationRecord

SCHEMA_MIGRATIONS_TABLE = "schema_migrations"

CREATE_SCHEMA_MIGRATIONS_DDL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL,
    execution_time_ms INTEGER NOT NULL,
    checksum TEXT
);
""".strip()


class SchemaInspector:
    """Inspects and manages schema_migrations metadata catalog across backends."""

    @staticmethod
    def ensure_schema_migrations_table(adapter: DatabaseAdapter) -> None:
        """
        Creates the schema_migrations management table if it does not already exist.
        Idempotent operation across both PyDB and SQLite.
        """
        adapter.execute_ddl(CREATE_SCHEMA_MIGRATIONS_DDL)

    @staticmethod
    def has_schema_migrations_table(adapter: DatabaseAdapter) -> bool:
        """
        Checks whether the schema_migrations table exists in the target database.
        """
        try:
            # Universal check: attempt to query schema_migrations directly
            adapter.execute_query(
                f"SELECT version FROM {SCHEMA_MIGRATIONS_TABLE} LIMIT 1"
            )
            return True
        except Exception:
            return False

    @staticmethod
    def get_applied_migrations(adapter: DatabaseAdapter) -> List[MigrationRecord]:
        """
        Retrieves all applied migrations ordered by version ascending.
        Returns empty list if schema_migrations table does not exist.
        """
        if not SchemaInspector.has_schema_migrations_table(adapter):
            return []

        query = (
            f"SELECT version, name, applied_at, execution_time_ms, checksum "
            f"FROM {SCHEMA_MIGRATIONS_TABLE} ORDER BY version ASC"
        )
        rows = adapter.execute_query(query)
        records: List[MigrationRecord] = []
        for row in rows:
            record = MigrationRecord(
                version=str(row[0]),
                name=str(row[1]),
                applied_at=str(row[2]),
                execution_time_ms=int(row[3]),
                checksum=str(row[4]) if row[4] is not None else None,
            )
            records.append(record)
        return records

    @staticmethod
    def record_migration(
        adapter: DatabaseAdapter,
        record: MigrationRecord,
    ) -> None:
        """
        Records an applied migration into the schema_migrations catalog.
        """
        SchemaInspector.ensure_schema_migrations_table(adapter)
        query = (
            f"INSERT INTO {SCHEMA_MIGRATIONS_TABLE} "
            f"(version, name, applied_at, execution_time_ms, checksum) "
            f"VALUES (?, ?, ?, ?, ?)"
        )
        conn = adapter.connect()
        cur = conn.cursor()
        try:
            cur.execute(
                query,
                (
                    record.version,
                    record.name,
                    record.applied_at,
                    record.execution_time_ms,
                    record.checksum,
                ),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise

    @staticmethod
    def remove_migration_record(
        adapter: DatabaseAdapter,
        version: str,
    ) -> None:
        """
        Removes an unapplied (rolled back) migration record from schema_migrations.
        """
        if not SchemaInspector.has_schema_migrations_table(adapter):
            return

        query = f"DELETE FROM {SCHEMA_MIGRATIONS_TABLE} WHERE version = ?"
        conn = adapter.connect()
        cur = conn.cursor()
        try:
            cur.execute(query, (version,))
            conn.commit()
        except Exception:
            conn.rollback()
            raise
