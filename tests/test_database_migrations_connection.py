#!/usr/bin/env python3
"""
Unit and integration tests for migration models, PEP 249 adapters, and SchemaInspector.
Covers both Primary (src/database Pure Python RDBMS) and Secondary (sqlite3) backends.
Conforms to Issue #384 DoD.
"""

from pathlib import Path

import pytest

from src.database.migrations import (
    BackendType,
    MigrationDirection,
    MigrationRecord,
    PyDBAdapter,
    SchemaInspector,
    SQLiteAdapter,
    get_adapter,
    parse_migration_filename,
    validate_migration_name,
)


class TestMigrationModels:
    """Tests for BackendType, MigrationStatus, and filename validation."""

    def test_backend_type_resolution(self) -> None:
        assert BackendType.from_str("pydb") == BackendType.PYDB
        assert BackendType.from_str("pure_python") == BackendType.PYDB
        assert BackendType.from_str("sqlite") == BackendType.SQLITE
        assert BackendType.from_str("sqlite3") == BackendType.SQLITE

        with pytest.raises(ValueError, match="Unsupported backend type"):
            BackendType.from_str("mysql")

    def test_validate_migration_name_valid(self) -> None:
        assert validate_migration_name("init_schema") == "init_schema"
        assert validate_migration_name("add_users_table_v2") == "add_users_table_v2"
        assert validate_migration_name("123_test") == "123_test"

    def test_validate_migration_name_invalid(self) -> None:
        with pytest.raises(ValueError, match="cannot be empty"):
            validate_migration_name("   ")

        with pytest.raises(ValueError, match="traversal"):
            validate_migration_name("../traversal")

        with pytest.raises(ValueError, match="traversal"):
            validate_migration_name("path/to/file")

        with pytest.raises(ValueError, match="must match pattern"):
            validate_migration_name("Invalid-Name-Hyphen")

        with pytest.raises(ValueError, match="must match pattern"):
            validate_migration_name("CapitalLetters")

    def test_parse_migration_filename_valid(self, tmp_path: Path) -> None:
        fname = "20260923000000_init_schema.up.sql"
        mf = parse_migration_filename(fname, base_dir=tmp_path)
        assert mf.version == "20260923000000"
        assert mf.name == "init_schema"
        assert mf.direction == MigrationDirection.UP.value
        assert mf.is_up is True
        assert mf.is_down is False
        assert mf.identifier == "20260923000000_init_schema"
        assert mf.filepath == tmp_path / fname

    def test_parse_migration_filename_down(self, tmp_path: Path) -> None:
        fname = "20260923120000_drop_table.down.sql"
        mf = parse_migration_filename(fname, base_dir=tmp_path)
        assert mf.is_down is True
        assert mf.direction == "down"

    def test_parse_migration_filename_invalid(self) -> None:
        with pytest.raises(ValueError, match="Invalid migration filename"):
            parse_migration_filename("invalid_filename.sql")

        with pytest.raises(ValueError, match="Invalid migration filename"):
            parse_migration_filename("20260923_short_version.up.sql")

        with pytest.raises(ValueError, match="Invalid migration filename"):
            parse_migration_filename("20260923000000_test.other.sql")

    def test_factory_get_adapter(self, tmp_path: Path) -> None:
        default_adapter = get_adapter(db_path=tmp_path / "default.vdb")
        assert isinstance(default_adapter, PyDBAdapter)
        assert default_adapter.backend_type == BackendType.PYDB

        pydb_adapter = get_adapter(
            backend=BackendType.PYDB, db_path=tmp_path / "custom.vdb"
        )
        assert isinstance(pydb_adapter, PyDBAdapter)

        sqlite_adapter = get_adapter(backend="sqlite", db_path=tmp_path / "custom.db")
        assert isinstance(sqlite_adapter, SQLiteAdapter)
        assert sqlite_adapter.backend_type == BackendType.SQLITE


class TestPyDBAdapter:
    """Tests for Primary backend (src/database Pure Python RDBMS)."""

    def test_pydb_adapter_lifecycle_and_ddl(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_pydb.vdb"
        adapter = PyDBAdapter(db_path=db_path)
        assert adapter.is_healthy() is True

        # Execute DDL
        adapter.execute_ddl(
            "CREATE TABLE test_items (id TEXT PRIMARY KEY, title TEXT);"
        )

        # Insert and select
        conn = adapter.connect()
        cur = conn.cursor()
        cur.execute("INSERT INTO test_items VALUES (?, ?)", ("item1", "Test Title"))
        conn.commit()

        rows = adapter.execute_query(
            "SELECT id, title FROM test_items WHERE id = ?", ("item1",)
        )
        assert len(rows) == 1
        assert rows[0][0] == "item1"
        assert rows[0][1] == "Test Title"

        adapter.close()

    def test_pydb_schema_inspector(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_schema.vdb"
        adapter = PyDBAdapter(db_path=db_path)

        assert SchemaInspector.has_schema_migrations_table(adapter) is False
        assert SchemaInspector.get_applied_migrations(adapter) == []

        # Ensure idempotency
        SchemaInspector.ensure_schema_migrations_table(adapter)
        SchemaInspector.ensure_schema_migrations_table(adapter)
        assert SchemaInspector.has_schema_migrations_table(adapter) is True

        # Record migration
        rec1 = MigrationRecord(
            version="20260923000000",
            name="init_schema",
            applied_at="2026-09-23T00:00:00Z",
            execution_time_ms=12,
            checksum="abc123hash",
        )
        SchemaInspector.record_migration(adapter, rec1)

        applied = SchemaInspector.get_applied_migrations(adapter)
        assert len(applied) == 1
        assert applied[0].version == "20260923000000"
        assert applied[0].name == "init_schema"
        assert applied[0].applied_at == "2026-09-23T00:00:00Z"
        assert applied[0].execution_time_ms == 12
        assert applied[0].checksum == "abc123hash"

        # Record second migration
        rec2 = MigrationRecord(
            version="20260923010000",
            name="add_index",
            applied_at="2026-09-23T01:00:00Z",
            execution_time_ms=5,
        )
        SchemaInspector.record_migration(adapter, rec2)

        applied2 = SchemaInspector.get_applied_migrations(adapter)
        assert len(applied2) == 2
        assert applied2[0].version == "20260923000000"
        assert applied2[1].version == "20260923010000"

        # Rollback (remove) rec2
        SchemaInspector.remove_migration_record(adapter, "20260923010000")
        applied3 = SchemaInspector.get_applied_migrations(adapter)
        assert len(applied3) == 1
        assert applied3[0].version == "20260923000000"

        adapter.close()


class TestSQLiteAdapter:
    """Tests for Secondary backend (sqlite3)."""

    def test_sqlite_adapter_lifecycle_and_ddl(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_sqlite.db"
        adapter = SQLiteAdapter(db_path=db_path)
        try:
            assert adapter.is_healthy() is True

            adapter.execute_ddl(
                "CREATE TABLE sample_items (id TEXT PRIMARY KEY, num INTEGER);"
            )

            conn = adapter.connect()
            cur = conn.cursor()
            cur.execute("INSERT INTO sample_items VALUES (?, ?)", ("k1", 42))
            conn.commit()

            rows = adapter.execute_query(
                "SELECT id, num FROM sample_items WHERE id = ?", ("k1",)
            )
            assert len(rows) == 1
            assert rows[0][0] == "k1"
            assert rows[0][1] == 42
        finally:
            adapter.close()

    def test_sqlite_schema_inspector(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_schema.db"
        adapter = SQLiteAdapter(db_path=db_path)
        try:
            assert SchemaInspector.has_schema_migrations_table(adapter) is False

            SchemaInspector.ensure_schema_migrations_table(adapter)
            SchemaInspector.ensure_schema_migrations_table(adapter)
            assert SchemaInspector.has_schema_migrations_table(adapter) is True

            rec = MigrationRecord(
                version="20260923000000",
                name="baseline",
                applied_at="2026-09-23T12:00:00Z",
                execution_time_ms=8,
                checksum="sqlite_sha",
            )
            SchemaInspector.record_migration(adapter, rec)

            applied = SchemaInspector.get_applied_migrations(adapter)
            assert len(applied) == 1
            assert applied[0].version == "20260923000000"
            assert applied[0].name == "baseline"
            assert applied[0].checksum == "sqlite_sha"

            SchemaInspector.remove_migration_record(adapter, "20260923000000")
            assert len(SchemaInspector.get_applied_migrations(adapter)) == 0
        finally:
            adapter.close()
