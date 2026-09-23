#!/usr/bin/env python3
"""
Unit and integration tests for MigrationManager orchestrator.
Covers create, get_migration_files, status, up, down across Primary (PyDB)
and Secondary (SQLite) backends with multi-step executions and error conditions.
Conforms to Issue #385 DoD.
"""

from pathlib import Path

import pytest

from src.database.migrations import (
    BackendType,
    MigrationFileNotFoundError,
    MigrationManager,
    MigrationStatus,
)


class TestMigrationManagerBasics:
    """Tests for file generation and scanning in MigrationManager."""

    def test_create_valid_migration_files(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.vdb"
        mig_dir = tmp_path / "migrations"
        manager = MigrationManager(
            db_path=db_path,
            migrations_dir=mig_dir,
            backend=BackendType.PYDB,
        )

        up_path, down_path = manager.create("create_papers_table")
        assert up_path.exists()
        assert down_path.exists()
        assert up_path.name.endswith("_create_papers_table.up.sql")
        assert down_path.name.endswith("_create_papers_table.down.sql")

        up_text = up_path.read_text(encoding="utf-8")
        assert "-- Migration: create_papers_table (UP)" in up_text
        assert "-- Version:" in up_text

        down_text = down_path.read_text(encoding="utf-8")
        assert "-- Migration: create_papers_table (DOWN)" in down_text
        manager.close()

    def test_create_invalid_names(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.vdb"
        manager = MigrationManager(db_path=db_path, migrations_dir=tmp_path / "migs")

        with pytest.raises(ValueError, match="must match pattern"):
            manager.create("invalid-name-hyphen")

        with pytest.raises(ValueError, match="traversal"):
            manager.create("../traversal_name")

        with pytest.raises(ValueError, match="cannot be empty"):
            manager.create("   ")
        manager.close()

    def test_get_migration_files_and_ordering(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test.vdb"
        mig_dir = tmp_path / "migrations"
        mig_dir.mkdir(parents=True, exist_ok=True)

        # Create out of order files
        (mig_dir / "20260923000003_third.up.sql").write_text("--", encoding="utf-8")
        (mig_dir / "20260923000003_third.down.sql").write_text("--", encoding="utf-8")
        (mig_dir / "20260923000001_first.up.sql").write_text("--", encoding="utf-8")
        (mig_dir / "20260923000001_first.down.sql").write_text("--", encoding="utf-8")
        (mig_dir / "20260923000002_second.up.sql").write_text("--", encoding="utf-8")
        (mig_dir / "20260923000002_second.down.sql").write_text("--", encoding="utf-8")

        # Non-migration file should be ignored
        (mig_dir / "readme.txt").write_text("ignore me", encoding="utf-8")

        manager = MigrationManager(db_path=db_path, migrations_dir=mig_dir)
        up_files = manager.get_migration_files(direction="up")
        assert len(up_files) == 3
        assert [f.version for f in up_files] == [
            "20260923000001",
            "20260923000002",
            "20260923000003",
        ]

        down_files = manager.get_migration_files(direction="down")
        assert len(down_files) == 3
        assert [f.version for f in down_files] == [
            "20260923000001",
            "20260923000002",
            "20260923000003",
        ]

        with pytest.raises(ValueError, match="Invalid direction"):
            manager.get_migration_files(direction="invalid")
        manager.close()


class TestMigrationManagerExecutionPyDB:
    """Tests for multi-step up/down/status on Primary backend (src/database Pure Python RDBMS)."""

    def test_pydb_full_lifecycle(self, tmp_path: Path) -> None:
        db_path = tmp_path / "lifecycle.vdb"
        mig_dir = tmp_path / "migs"
        mig_dir.mkdir(parents=True, exist_ok=True)

        # 1. Prepare 3 migrations
        (mig_dir / "20260923000001_create_t1.up.sql").write_text(
            "CREATE TABLE t1 (id TEXT PRIMARY KEY, val TEXT);", encoding="utf-8"
        )
        (mig_dir / "20260923000001_create_t1.down.sql").write_text(
            "DROP TABLE t1;", encoding="utf-8"
        )

        (mig_dir / "20260923000002_create_t2.up.sql").write_text(
            "CREATE TABLE t2 (id TEXT PRIMARY KEY, num INTEGER);", encoding="utf-8"
        )
        (mig_dir / "20260923000002_create_t2.down.sql").write_text(
            "DROP TABLE t2;", encoding="utf-8"
        )

        (mig_dir / "20260923000003_create_t3.up.sql").write_text(
            "CREATE TABLE t3 (id TEXT PRIMARY KEY);", encoding="utf-8"
        )
        (mig_dir / "20260923000003_create_t3.down.sql").write_text(
            "DROP TABLE t3;", encoding="utf-8"
        )

        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend=BackendType.PYDB
        ) as mgr:
            # Check initial status
            init_status = mgr.status()
            assert len(init_status) == 3
            assert all(
                s["status"] == MigrationStatus.PENDING.value for s in init_status
            )

            # Apply 2 steps
            applied_2 = mgr.up(steps=2)
            assert len(applied_2) == 2
            assert applied_2[0].version == "20260923000001"
            assert applied_2[1].version == "20260923000002"

            status_2 = mgr.status()
            assert status_2[0]["status"] == MigrationStatus.APPLIED.value
            assert status_2[1]["status"] == MigrationStatus.APPLIED.value
            assert status_2[2]["status"] == MigrationStatus.PENDING.value

            # Apply remaining
            applied_rest = mgr.up()
            assert len(applied_rest) == 1
            assert applied_rest[0].version == "20260923000003"

            # Re-run up (idempotent, 0 pending)
            assert mgr.up() == []

            # Rollback 1 step (t3)
            rolled_back_1 = mgr.down(steps=1)
            assert rolled_back_1 == ["20260923000003"]
            status_after_down1 = mgr.status()
            assert status_after_down1[2]["status"] == MigrationStatus.PENDING.value

            # Rollback remaining 2 steps (t2, t1)
            rolled_back_2 = mgr.down(steps=2)
            assert rolled_back_2 == ["20260923000002", "20260923000001"]

            final_status = mgr.status()
            assert all(
                s["status"] == MigrationStatus.PENDING.value for s in final_status
            )

            # Down on empty should return empty list
            assert mgr.down() == []


class TestMigrationManagerExecutionSQLite:
    """Tests for multi-step up/down/status on Secondary backend (sqlite3)."""

    def test_sqlite_full_lifecycle(self, tmp_path: Path) -> None:
        db_path = tmp_path / "lifecycle.db"
        mig_dir = tmp_path / "migs_sqlite"
        mig_dir.mkdir(parents=True, exist_ok=True)

        (mig_dir / "20260923000001_create_s1.up.sql").write_text(
            "CREATE TABLE s1 (id TEXT PRIMARY KEY);", encoding="utf-8"
        )
        (mig_dir / "20260923000001_create_s1.down.sql").write_text(
            "DROP TABLE s1;", encoding="utf-8"
        )

        (mig_dir / "20260923000002_create_s2.up.sql").write_text(
            "CREATE TABLE s2 (id TEXT PRIMARY KEY);", encoding="utf-8"
        )
        (mig_dir / "20260923000002_create_s2.down.sql").write_text(
            "DROP TABLE s2;", encoding="utf-8"
        )

        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend="sqlite"
        ) as mgr:
            # Check initial status
            assert len(mgr.status()) == 2
            assert mgr.status()[0]["status"] == MigrationStatus.PENDING.value

            # Up all
            applied = mgr.up()
            assert len(applied) == 2

            # Status all applied
            assert all(
                s["status"] == MigrationStatus.APPLIED.value for s in mgr.status()
            )

            # Down 1
            rolled_back = mgr.down(steps=1)
            assert rolled_back == ["20260923000002"]
            assert mgr.status()[1]["status"] == MigrationStatus.PENDING.value

    def test_sqlite_down_missing_file_error(self, tmp_path: Path) -> None:
        db_path = tmp_path / "missing_down.db"
        mig_dir = tmp_path / "migs_missing"
        mig_dir.mkdir(parents=True, exist_ok=True)

        (mig_dir / "20260923000001_init.up.sql").write_text(
            "CREATE TABLE init_tbl (id TEXT PRIMARY KEY);", encoding="utf-8"
        )
        # Note: .down.sql is deliberately NOT created!

        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend=BackendType.SQLITE
        ) as mgr:
            mgr.up()
            with pytest.raises(
                MigrationFileNotFoundError, match="Required rollback file not found"
            ):
                mgr.down(steps=1)

    def test_down_non_positive_steps(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_down_zero.db"
        mig_dir = tmp_path / "migs_zero"
        mig_dir.mkdir(parents=True, exist_ok=True)
        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend="sqlite"
        ) as mgr:
            assert mgr.down(steps=0) == []
            assert mgr.down(steps=-5) == []

    def test_default_migrations_dir(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_default_dir.db"
        mgr = MigrationManager(db_path=db_path)
        try:
            assert mgr.migrations_dir.name == "migrations"
            assert mgr.migrations_dir.exists()
        finally:
            mgr.close()

    def test_status_with_untracked_applied_migration(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_untracked.db"
        mig_dir = tmp_path / "migs_untracked"
        mig_dir.mkdir(parents=True, exist_ok=True)

        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend="sqlite"
        ) as mgr:
            # Insert a record directly into schema_migrations without a local .up.sql file
            from src.database.migrations import MigrationRecord, SchemaInspector

            rec = MigrationRecord(
                version="20260923999999",
                name="external_migration",
                applied_at="2026-09-23T12:00:00Z",
                execution_time_ms=10,
            )
            SchemaInspector.record_migration(mgr.adapter, rec)

            status_list = mgr.status()
            assert len(status_list) == 1
            assert status_list[0]["version"] == "20260923999999"
            assert status_list[0]["name"] == "external_migration"
            assert status_list[0]["status"] == MigrationStatus.APPLIED.value

    def test_get_migration_files_with_subdirectories_and_missing_dir(
        self, tmp_path: Path
    ) -> None:
        db_path = tmp_path / "test_subdirs.db"
        mig_dir = tmp_path / "migs_subdirs"
        mig_dir.mkdir(parents=True, exist_ok=True)
        (mig_dir / "subdir").mkdir()
        (mig_dir / "random.txt").write_text("not a migration", encoding="utf-8")

        with MigrationManager(
            db_path=db_path, migrations_dir=mig_dir, backend="sqlite"
        ) as mgr:
            assert mgr.get_migration_files(direction="up") == []

        non_existent = tmp_path / "ghost_dir"
        mgr_ghost = MigrationManager(
            db_path=db_path, migrations_dir=non_existent, backend="sqlite"
        )
        try:
            # Force remove to test non-existent check
            non_existent.rmdir()
            assert mgr_ghost.get_migration_files(direction="up") == []
        finally:
            mgr_ghost.close()
