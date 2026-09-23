#!/usr/bin/env python3
"""
Unit and integration tests for MigrationRunner.
Covers atomic transaction execution, script splitting, checksum computation,
and rollback on error across Primary (src/database) and Secondary (sqlite3) backends.
Conforms to Issue #385 DoD.
"""

from pathlib import Path

import pytest

from src.database.migrations import (
    MigrationExecutionError,
    MigrationFile,
    MigrationFileNotFoundError,
    MigrationRunner,
    PyDBAdapter,
    SchemaInspector,
    SQLiteAdapter,
)


class TestMigrationRunnerUtils:
    """Tests for SQL statement splitting and checksum calculations."""

    def test_split_sql_statements(self) -> None:
        raw_sql = """
        -- Header comment
        CREATE TABLE users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL
        );

        -- Another comment
        CREATE INDEX idx_users_username ON users(username);

        INSERT INTO users VALUES ('u1', 'alice');
        """
        stmts = MigrationRunner.split_sql_statements(raw_sql)
        assert len(stmts) == 3
        assert stmts[0].startswith("CREATE TABLE users")
        assert stmts[1].startswith("CREATE INDEX idx_users_username")
        assert stmts[2].startswith("INSERT INTO users")

    def test_split_sql_empty_and_comments(self) -> None:
        raw_sql = """
        -- Just a comment
        -- Another comment
        """
        assert MigrationRunner.split_sql_statements(raw_sql) == []
        assert MigrationRunner.split_sql_statements("") == []
        assert MigrationRunner.split_sql_statements("   \n\n  ") == []

    def test_compute_checksum(self) -> None:
        content = "CREATE TABLE dummy (id TEXT PRIMARY KEY);"
        checksum1 = MigrationRunner.compute_checksum(content)
        checksum2 = MigrationRunner.compute_checksum(content)
        assert checksum1 == checksum2
        assert len(checksum1) == 64  # SHA-256 hex string


class TestMigrationRunnerPyDB:
    """Tests for MigrationRunner against Primary backend (src/database Pure Python RDBMS)."""

    def test_apply_and_rollback_pydb(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_pydb_runner.vdb"
        adapter = PyDBAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        up_file = tmp_path / "20260923000001_create_posts.up.sql"
        up_file.write_text(
            """
            CREATE TABLE posts (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL
            );
            INSERT INTO posts VALUES ('p1', 'First Post');
            """,
            encoding="utf-8",
        )

        mf_up = MigrationFile(
            version="20260923000001",
            name="create_posts",
            direction="up",
            filepath=up_file,
        )

        # 1. Apply migration
        record = runner.apply(mf_up)
        assert record.version == "20260923000001"
        assert record.name == "create_posts"
        assert record.execution_time_ms >= 0
        assert record.checksum is not None

        # Verify post-condition
        applied = SchemaInspector.get_applied_migrations(adapter)
        assert len(applied) == 1
        assert applied[0].version == "20260923000001"

        rows = adapter.execute_query("SELECT id, title FROM posts")
        assert len(rows) == 1
        assert rows[0][0] == "p1"
        assert rows[0][1] == "First Post"

        # 2. Rollback migration
        down_file = tmp_path / "20260923000001_create_posts.down.sql"
        down_file.write_text("DROP TABLE posts;", encoding="utf-8")

        mf_down = MigrationFile(
            version="20260923000001",
            name="create_posts",
            direction="down",
            filepath=down_file,
        )

        runner.rollback(mf_down)
        applied_after = SchemaInspector.get_applied_migrations(adapter)
        assert len(applied_after) == 0

        # Table should be dropped
        conn = adapter.connect()
        assert "posts" not in conn.tables
        adapter.close()

    def test_pydb_atomic_rollback_on_failure(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_pydb_fail.vdb"
        adapter = PyDBAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        up_file = tmp_path / "20260923000002_broken.up.sql"
        up_file.write_text(
            """
            CREATE TABLE fail_table (id TEXT PRIMARY KEY);
            THIS IS INVALID SQL STATEMENT AND MUST FAIL;
            """,
            encoding="utf-8",
        )

        mf = MigrationFile(
            version="20260923000002",
            name="broken",
            direction="up",
            filepath=up_file,
        )

        with pytest.raises(MigrationExecutionError):
            runner.apply(mf)

        # Ensure fail_table does not exist and schema_migrations is clean
        conn = adapter.connect()
        assert "fail_table" not in conn.tables
        assert len(SchemaInspector.get_applied_migrations(adapter)) == 0
        adapter.close()


class TestMigrationRunnerSQLite:
    """Tests for MigrationRunner against Secondary backend (sqlite3)."""

    def test_apply_and_rollback_sqlite(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_sqlite_runner.db"
        adapter = SQLiteAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        up_file = tmp_path / "20260923000003_create_authors.up.sql"
        up_file.write_text(
            """
            CREATE TABLE authors (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            INSERT INTO authors VALUES ('a1', 'Dr. Smith');
            """,
            encoding="utf-8",
        )

        mf_up = MigrationFile(
            version="20260923000003",
            name="create_authors",
            direction="up",
            filepath=up_file,
        )

        # 1. Apply
        record = runner.apply(mf_up)
        assert record.version == "20260923000003"
        assert record.name == "create_authors"

        rows = adapter.execute_query("SELECT id, name FROM authors")
        assert len(rows) == 1
        assert rows[0][1] == "Dr. Smith"

        # 2. Rollback
        down_file = tmp_path / "20260923000003_create_authors.down.sql"
        down_file.write_text("DROP TABLE authors;", encoding="utf-8")

        mf_down = MigrationFile(
            version="20260923000003",
            name="create_authors",
            direction="down",
            filepath=down_file,
        )

        runner.rollback(mf_down)
        assert len(SchemaInspector.get_applied_migrations(adapter)) == 0
        adapter.close()

    def test_sqlite_atomic_rollback_on_failure(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_sqlite_fail.db"
        adapter = SQLiteAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        up_file = tmp_path / "20260923000004_broken_sqlite.up.sql"
        up_file.write_text(
            """
            CREATE TABLE should_not_exist (id TEXT PRIMARY KEY);
            SYNTAX ERROR AT LINE 2;
            """,
            encoding="utf-8",
        )

        mf = MigrationFile(
            version="20260923000004",
            name="broken_sqlite",
            direction="up",
            filepath=up_file,
        )

        with pytest.raises(MigrationExecutionError):
            runner.apply(mf)

        # Verify table was rolled back
        rows = adapter.execute_query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='should_not_exist'"
        )
        assert len(rows) == 0
        assert len(SchemaInspector.get_applied_migrations(adapter)) == 0
        adapter.close()

    def test_missing_migration_file(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_missing.db"
        adapter = SQLiteAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        non_existent_file = tmp_path / "20260923000005_ghost.up.sql"
        mf = MigrationFile(
            version="20260923000005",
            name="ghost",
            direction="up",
            filepath=non_existent_file,
        )

        with pytest.raises(MigrationFileNotFoundError):
            runner.apply(mf)

        with pytest.raises(MigrationFileNotFoundError):
            runner.rollback(mf)

        adapter.close()

    def test_rollback_execution_failure(self, tmp_path: Path) -> None:
        db_path = tmp_path / "test_rollback_fail.db"
        adapter = SQLiteAdapter(db_path=db_path)
        runner = MigrationRunner(adapter=adapter)

        up_file = tmp_path / "20260923000006_valid.up.sql"
        up_file.write_text(
            "CREATE TABLE valid_tbl (id TEXT PRIMARY KEY);", encoding="utf-8"
        )
        mf_up = MigrationFile(
            version="20260923000006", name="valid", direction="up", filepath=up_file
        )
        runner.apply(mf_up)

        down_file = tmp_path / "20260923000006_valid.down.sql"
        down_file.write_text("INVALID SQL STATEMENT IN DOWN;", encoding="utf-8")
        mf_down = MigrationFile(
            version="20260923000006", name="valid", direction="down", filepath=down_file
        )

        with pytest.raises(MigrationExecutionError):
            runner.rollback(mf_down)

        adapter.close()

    def test_get_table_names_exception_fallback(self) -> None:
        class BrokenConnection:
            def cursor(self) -> None:
                raise RuntimeError("Cursor failed")

        runner = MigrationRunner(adapter=SQLiteAdapter(db_path=":memory:"))
        assert runner._get_table_names(BrokenConnection()) == []

    def test_cleanup_failed_tables_exception_paths(self) -> None:
        class FailingCur:
            def execute(self, sql: str) -> None:
                raise RuntimeError("Drop error")

        class FailingConn:
            tables = ["t_new"]

            def commit(self) -> None:
                raise RuntimeError("Commit error")

        runner = MigrationRunner(adapter=SQLiteAdapter(db_path=":memory:"))
        runner._cleanup_failed_tables(FailingConn(), FailingCur(), initial_tables=set())
