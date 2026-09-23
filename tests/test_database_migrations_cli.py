#!/usr/bin/env python3
"""
Unit and integration tests for database migrations CLI command.
Covers MigrationsCommand, CommandDispatcher routing, dual backends (PyDB and SQLite),
subcommands (create, up, down, status), formatting, and error handling.
Conforms to DSN-30 and Issue #386 DoD.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest

from src.cli.dispatcher import CommandDispatcher
from src.cli.registry import get_command_class, list_available_commands
from src.database.migrations import BackendType, MigrationsCommand
from src.database.migrations.cli import (
    _count_by_status,
    _format_table_row,
    _render_table,
    _resolve_migrations_dir,
    _resolve_target_db,
)


class TestMigrationsCliHelpers:
    """Tests for CLI path resolution, row formatting, and helper utilities."""

    def test_resolve_target_db_defaults(self, tmp_path: Path) -> None:
        args = argparse.Namespace(db_path=None)
        pydb_path = _resolve_target_db(args, BackendType.PYDB, workspace_dir=None)
        assert pydb_path == "data/arxiv_papers.vdb"

        sqlite_path = _resolve_target_db(args, BackendType.SQLITE, workspace_dir=None)
        assert sqlite_path == "data/arxiv_papers.db"

    def test_resolve_target_db_workspace(self, tmp_path: Path) -> None:
        args = argparse.Namespace(db_path=None)
        resolved = _resolve_target_db(
            args, BackendType.PYDB, workspace_dir=str(tmp_path)
        )
        assert resolved == str(tmp_path / "data/arxiv_papers.vdb")

    def test_resolve_target_db_explicit(self, tmp_path: Path) -> None:
        custom = tmp_path / "custom.db"
        args = argparse.Namespace(db_path=str(custom))
        resolved = _resolve_target_db(
            args, BackendType.SQLITE, workspace_dir=str(tmp_path)
        )
        assert resolved == str(custom)

    def test_resolve_migrations_dir(self, tmp_path: Path) -> None:
        # Explicit arg
        args_explicit = argparse.Namespace(migrations_dir="/tmp/custom_migs")
        assert (
            _resolve_migrations_dir(args_explicit, workspace_dir=None)
            == "/tmp/custom_migs"
        )

        # Workspace with existing migrations/ dir
        mig_dir = tmp_path / "migrations"
        mig_dir.mkdir()
        args_empty = argparse.Namespace(migrations_dir=None)
        resolved = _resolve_migrations_dir(args_empty, workspace_dir=str(tmp_path))
        assert resolved == str(mig_dir)

        # Workspace without migrations/ dir
        empty_ws = tmp_path / "empty_ws"
        empty_ws.mkdir()
        assert _resolve_migrations_dir(args_empty, workspace_dir=str(empty_ws)) is None

    def test_count_by_status(self) -> None:
        records = [
            {"status": "Applied"},
            {"status": "Pending"},
            {"status": "Applied"},
            {"status": "Untracked"},
        ]
        assert _count_by_status(records, "Applied") == 2
        assert _count_by_status(records, "Pending") == 1
        assert _count_by_status(records, "Missing") == 0

    def test_format_table_row(self) -> None:
        record = {
            "version": "20260923000000",
            "name": "create_users_table_very_long_name_exceeding_thirty_chars",
            "status": "Applied",
            "applied_at": "2026-09-23 10:00:00",
        }
        row = _format_table_row(record)
        assert "| 20260923000000 |" in row
        assert "Applied " in row
        assert "2026-09-23 10:00:00" in row

    def test_render_table_output(self, capsys: pytest.CaptureFixture[str]) -> None:
        records = [
            {
                "version": "20260923000000",
                "name": "baseline",
                "status": "Applied",
                "applied_at": "2026-09-23 10:00:00",
            },
            {
                "version": "20260924000000",
                "name": "add_index",
                "status": "Pending",
                "applied_at": None,
            },
        ]
        _render_table(records, BackendType.PYDB, "data/arxiv_papers.vdb")
        captured = capsys.readouterr().out
        expected_fragments = [
            "Primary (src.database / Pure Python RDBMS)",
            "Database: data/arxiv_papers.vdb",
            "20260923000000",
            "add_index",
            "Total: 2 migrations (1 applied, 1 pending)",
        ]
        assert all(frag in captured for frag in expected_fragments)


class TestMigrationsCommandExecution:
    """Tests executing subcommands via MigrationsCommand."""

    @pytest.fixture
    def setup_env(self, tmp_path: Path) -> dict[str, Any]:
        db_path = tmp_path / "test.db"
        mig_dir = tmp_path / "migrations"
        mig_dir.mkdir(parents=True, exist_ok=True)
        return {"db_path": db_path, "mig_dir": mig_dir, "ws_dir": tmp_path}

    def test_command_metadata(self) -> None:
        cmd = MigrationsCommand()
        assert cmd.name == "migrations"
        assert "DSN-30" in cmd.help_text

    def test_create_subcommand_success(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()
        args = parser.parse_args(
            [
                "create",
                "add_papers_table",
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )

        ret = cmd.handle(args)
        assert ret == 0
        captured = capsys.readouterr()
        assert "[OK] Created:" in captured.out
        created_files = list(setup_env["mig_dir"].glob("*.sql"))
        assert len(created_files) == 2

    def test_create_subcommand_invalid_name(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()
        args = parser.parse_args(
            [
                "create",
                "Invalid-Name!",
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )

        ret = cmd.handle(args)
        assert ret == 2
        captured = capsys.readouterr()
        assert "[ERROR] Invalid argument:" in captured.err

    def _prepare_two_sqlite_migrations(self, mig_dir: Path) -> None:
        up1 = mig_dir / "20260923000001_create_t1.up.sql"
        up1.write_text("CREATE TABLE t1 (id INT PRIMARY KEY);", encoding="utf-8")
        down1 = mig_dir / "20260923000001_create_t1.down.sql"
        down1.write_text("DROP TABLE t1;", encoding="utf-8")

        up2 = mig_dir / "20260923000002_create_t2.up.sql"
        up2.write_text("CREATE TABLE t2 (id INT PRIMARY KEY);", encoding="utf-8")
        down2 = mig_dir / "20260923000002_create_t2.down.sql"
        down2.write_text("DROP TABLE t2;", encoding="utf-8")

    def test_sqlite_status_pending(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        self._prepare_two_sqlite_migrations(setup_env["mig_dir"])
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()

        args_status = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "status",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args_status) == 0
        captured = capsys.readouterr()
        assert "Total: 2 migrations (0 applied, 2 pending)" in captured.out

    def test_sqlite_up_lifecycle(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        self._prepare_two_sqlite_migrations(setup_env["mig_dir"])
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()

        args_up_1 = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "up",
                "--steps",
                "1",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args_up_1) == 0

        args_up_all = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "up",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args_up_all) == 0
        assert cmd.handle(args_up_all) == 0

    def test_sqlite_down_lifecycle(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        self._prepare_two_sqlite_migrations(setup_env["mig_dir"])
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()

        # apply all first
        args_up_all = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "up",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        cmd.handle(args_up_all)
        capsys.readouterr()

        # down twice
        args_down = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "down",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args_down) == 0
        assert cmd.handle(args_down) == 0
        assert cmd.handle(args_down) == 0
        captured = capsys.readouterr()
        assert "Nothing to rollback on [sqlite]." in captured.out

    def _prepare_pydb_migration(self, mig_dir: Path) -> None:
        up1 = mig_dir / "20260923000001_pydb_table.up.sql"
        up1.write_text(
            "CREATE TABLE pydb_t1 (id INT PRIMARY KEY, name TEXT);", encoding="utf-8"
        )
        down1 = mig_dir / "20260923000001_pydb_table.down.sql"
        down1.write_text("DROP TABLE pydb_t1;", encoding="utf-8")

    def test_pydb_lifecycle(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        db_path = tmp_path / "test.vdb"
        mig_dir = tmp_path / "migrations"
        mig_dir.mkdir(parents=True, exist_ok=True)
        self._prepare_pydb_migration(mig_dir)

        cmd = MigrationsCommand(workspace_dir=str(tmp_path))
        parser = cmd.create_parser()

        # up (default backend is pydb)
        args_up = parser.parse_args(
            [
                "up",
                "--backend",
                "pydb",
                "--db-path",
                str(db_path),
                "--migrations-dir",
                str(mig_dir),
            ]
        )
        assert cmd.handle(args_up) == 0

        # status
        args_status = parser.parse_args(
            [
                "status",
                "--backend",
                "pydb",
                "--db-path",
                str(db_path),
                "--migrations-dir",
                str(mig_dir),
            ]
        )
        assert cmd.handle(args_status) == 0

        # down
        args_down = parser.parse_args(
            [
                "down",
                "--backend",
                "pydb",
                "--db-path",
                str(db_path),
                "--migrations-dir",
                str(mig_dir),
            ]
        )
        assert cmd.handle(args_down) == 0
        captured = capsys.readouterr()
        assert "[OK] Rolled back migration: 20260923000001 on [pydb]" in captured.out

    def test_status_empty(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()
        args = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "status",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args) == 0
        captured = capsys.readouterr()
        assert "No migrations found on [sqlite]." in captured.out

    def test_up_syntax_error_returns_1(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        bad_up = setup_env["mig_dir"] / "20260923000001_bad.up.sql"
        bad_up.write_text("INVALID SYNTAX DDL ???;", encoding="utf-8")
        bad_down = setup_env["mig_dir"] / "20260923000001_bad.down.sql"
        bad_down.write_text("SELECT 1;", encoding="utf-8")

        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()
        args = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "up",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        ret = cmd.handle(args)
        assert ret == 1
        captured = capsys.readouterr()
        assert "[ERROR] Migration failed:" in captured.err

    def test_down_missing_file_returns_1(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        up = setup_env["mig_dir"] / "20260923000001_no_down.up.sql"
        up.write_text("CREATE TABLE t_no_down (id INT);", encoding="utf-8")
        # Do not create .down.sql

        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        parser = cmd.create_parser()
        args_up = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "up",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        assert cmd.handle(args_up) == 0

        # Now try to rollback
        args_down = parser.parse_args(
            [
                "--backend",
                "sqlite",
                "down",
                "--db-path",
                str(setup_env["db_path"]),
                "--migrations-dir",
                str(setup_env["mig_dir"]),
            ]
        )
        ret = cmd.handle(args_down)
        assert ret == 1
        captured = capsys.readouterr()
        assert (
            "[ERROR] Migration failed: Required rollback file not found" in captured.err
        )

    def test_invalid_backend_returns_2(
        self, setup_env: dict[str, Any], capsys: pytest.CaptureFixture[str]
    ) -> None:
        cmd = MigrationsCommand(workspace_dir=str(setup_env["ws_dir"]))
        args = argparse.Namespace(
            backend="unsupported_backend", migration_action="status"
        )
        ret = cmd.handle(args)
        assert ret == 2
        captured = capsys.readouterr()
        assert "[ERROR] Invalid backend" in captured.err


class TestRegistryAndDispatcherIntegration:
    """Tests integrating MigrationsCommand into CLI registry, dispatcher, and entrypoints."""

    def test_registry_contains_migrations(self) -> None:
        commands = list_available_commands()
        assert "migrations" in commands

        cls = get_command_class("migrations")
        assert cls is not None
        assert cls.__name__ == "MigrationsCommand"
        assert any(base.__name__ == "BaseCommand" for base in cls.__mro__)

    def test_dispatcher_migrations_help(
        self, capsys: pytest.CaptureFixture[str]
    ) -> None:
        dispatcher = CommandDispatcher(workspace_dir=".")
        with pytest.raises(SystemExit) as exc_info:
            dispatcher.run(["migrations", "--help"])
        assert exc_info.value.code == 0
        captured = capsys.readouterr()
        assert "Database schema migration management" in captured.out
        assert "{create,up,down,status}" in captured.out

    def test_dispatcher_migrations_execution(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        mig_dir = tmp_path / "migrations"
        mig_dir.mkdir(parents=True, exist_ok=True)
        dispatcher = CommandDispatcher(workspace_dir=str(tmp_path))

        ret = dispatcher.run(
            [
                "migrations",
                "create",
                "sample_migration",
                "--migrations-dir",
                str(mig_dir),
            ]
        )
        assert ret == 0
        captured = capsys.readouterr()
        assert "[OK] Created:" in captured.out
        assert len(list(mig_dir.glob("*.sql"))) == 2

    def test_manage_py_and_cli_py_entrypoints(self) -> None:
        import runpy

        with patch("sys.argv", ["manage.py", "--help"]):
            with pytest.raises(SystemExit) as exc:
                runpy.run_path("manage.py", run_name="__main__")
            assert exc.value.code == 0

        with patch("sys.argv", ["src/cli.py", "--help"]):
            with pytest.raises(SystemExit) as exc:
                runpy.run_path("src/cli.py", run_name="__main__")
            assert exc.value.code == 0
