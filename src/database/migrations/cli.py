#!/usr/bin/env python3
"""src/database/migrations/cli.py

Database migration subcommand for src/cli.py and manage.py.
Supports --backend=pydb (Primary) and --backend=sqlite (Secondary).
Conforms to DSN-24 and DSN-30, self-contained within migrations package.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

try:
    from cli.base import BaseCommand
except (ImportError, ValueError):
    from ...cli.base import BaseCommand  # type: ignore

from .manager import MigrationManager
from .models import BackendType, MigrationError


def _resolve_target_db(
    args: argparse.Namespace, backend: BackendType, workspace_dir: Optional[str]
) -> str:
    """Determines target database path from CLI args or default configuration."""
    explicit_path = getattr(args, "db_path", None)
    if explicit_path:
        db_path = str(explicit_path)
    elif backend == BackendType.PYDB:
        db_path = "data/arxiv_papers.vdb"
    else:
        db_path = "data/arxiv_papers.db"

    if workspace_dir and not os.path.isabs(db_path):
        return str(Path(workspace_dir) / db_path)
    return db_path


def _resolve_migrations_dir(
    args: argparse.Namespace, workspace_dir: Optional[str]
) -> Optional[str]:
    """Resolves migrations directory path accounting for custom args and workspace."""
    custom_dir = getattr(args, "migrations_dir", None)
    if custom_dir:
        return str(custom_dir)
    if workspace_dir:
        default_dir = Path(workspace_dir) / "migrations"
        if default_dir.exists():
            return str(default_dir)
    return None


def _count_by_status(records: Sequence[Dict[str, Any]], target_status: str) -> int:
    """Counts records matching a specific status (case-insensitive)."""
    target = target_status.upper()
    return sum(1 for r in records if str(r.get("status", "")).upper() == target)


def _format_table_row(r: Dict[str, Any]) -> str:
    """Formats a single migration status record as an ASCII table row."""
    ver = str(r["version"])
    name = str(r["name"])[:30].ljust(30)
    status = str(r["status"]).ljust(8)
    applied_at = str(r.get("applied_at") or "-")[:19].ljust(19)
    return f"| {ver} | {name} | {status} | {applied_at} |"


def _render_table(
    records: List[Dict[str, Any]], backend: BackendType, db_path: str
) -> None:
    """Prints formatted ASCII table conforming to DSN-30 Section 7.1."""
    target_label = (
        "Primary (src.database / Pure Python RDBMS)"
        if backend == BackendType.PYDB
        else "Secondary (sqlite3 / Bridge)"
    )
    sys.stdout.write(f"Backend:  {target_label}\n")
    sys.stdout.write(f"Database: {db_path}\n")
    border = "+----------------+--------------------------------+----------+---------------------+"
    sys.stdout.write(border + "\n")
    sys.stdout.write(
        "| Version        | Name                           | Status   | Applied At (UTC)    |\n"
    )
    sys.stdout.write(border + "\n")
    for r in records:
        sys.stdout.write(_format_table_row(r) + "\n")
    sys.stdout.write(border + "\n")
    applied_cnt = _count_by_status(records, "APPLIED")
    pending_cnt = _count_by_status(records, "PENDING")
    sys.stdout.write(
        f"Total: {len(records)} migrations ({applied_cnt} applied, {pending_cnt} pending)\n"
    )


def _handle_create(manager: MigrationManager, name: str) -> int:
    """Handles migration skeleton generation."""
    up_path, down_path = manager.create(name)
    sys.stdout.write(f"[OK] Created: {up_path}\n")
    sys.stdout.write(f"[OK] Created: {down_path}\n")
    return 0


def _handle_up(
    manager: MigrationManager, backend_label: str, steps: Optional[int]
) -> int:
    """Handles applying forward migrations."""
    applied = manager.up(steps=steps)
    if not applied:
        sys.stdout.write(f"No pending migrations to apply on [{backend_label}].\n")
        return 0
    for rec in applied:
        sys.stdout.write(
            f"[OK] Applied migration: {rec.version}_{rec.name} on [{backend_label}]\n"
        )
    return 0


def _handle_down(manager: MigrationManager, backend_label: str, steps: int) -> int:
    """Handles rolling back latest migrations."""
    rolled_back = manager.down(steps=steps)
    if not rolled_back:
        sys.stdout.write(f"Nothing to rollback on [{backend_label}].\n")
        return 0
    for v in rolled_back:
        sys.stdout.write(f"[OK] Rolled back migration: {v} on [{backend_label}]\n")
    return 0


def _handle_status(
    manager: MigrationManager, backend: BackendType, db_path: str
) -> int:
    """Handles displaying migration status."""
    records = manager.status()
    if not records:
        sys.stdout.write(f"No migrations found on [{backend.value}].\n")
        return 0
    _render_table(records, backend, db_path)
    return 0


_ACTION_HANDLERS: Dict[
    str,
    Any,
] = {
    "create": lambda m, a, b, db: _handle_create(m, str(a.name)),
    "up": lambda m, a, b, db: _handle_up(m, b.value, getattr(a, "steps", None)),
    "down": lambda m, a, b, db: _handle_down(m, b.value, getattr(a, "steps", 1) or 1),
    "status": lambda m, a, b, db: _handle_status(m, b, db),
}


def _dispatch_action(
    manager: MigrationManager,
    args: argparse.Namespace,
    backend_type: BackendType,
    resolved_db: str,
) -> int:
    """Dispatches to specific action handler using lookup table."""
    action = getattr(args, "migration_action", None)
    handler = _ACTION_HANDLERS.get(str(action))
    if not handler:
        sys.stderr.write(f"[ERROR] Unknown migration action: {action}\n")
        return 1
    return int(handler(manager, args, backend_type, resolved_db))


def _run_with_manager(
    resolved_db: str,
    resolved_dir: Optional[str],
    backend_type: BackendType,
    args: argparse.Namespace,
) -> int:
    """Executes manager operations with comprehensive error boundary."""
    try:
        with MigrationManager(
            db_path=resolved_db,
            migrations_dir=resolved_dir,
            backend=backend_type,
        ) as manager:
            return _dispatch_action(manager, args, backend_type, resolved_db)
    except MigrationError as ex:
        sys.stderr.write(f"[ERROR] Migration failed: {ex}\n")
        return 1
    except ValueError as ex:
        sys.stderr.write(f"[ERROR] Invalid argument: {ex}\n")
        return 2
    except Exception as ex:
        sys.stderr.write(f"[FATAL] Unexpected error: {ex}\n")
        return 1


class MigrationsCommand(BaseCommand):
    """Manage database schema migrations for Primary (src.database) and Secondary (sqlite3)."""

    name = "migrations"
    help_text = "Database schema migration management (DSN-30)"
    description = "Database schema migration management (DSN-30)"

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        """Configures subcommands and global flags for migrations CLI."""
        parser.add_argument(
            "--backend",
            choices=["pydb", "sqlite"],
            default="pydb",
            help="Target database engine: 'pydb' (Primary: src.database) or 'sqlite' (Secondary). Default: pydb.",
        )
        subparsers = parser.add_subparsers(dest="migration_action", required=True)

        create_p = subparsers.add_parser(
            "create", help="Create a new migration skeleton"
        )
        create_p.add_argument("name", help="Migration name in snake_case")
        create_p.add_argument(
            "--migrations-dir",
            default=argparse.SUPPRESS,
            help="Custom migrations directory",
        )

        up_p = subparsers.add_parser("up", help="Apply pending migrations")
        self._add_action_arguments(up_p)
        up_p.add_argument(
            "--steps", type=int, default=None, help="Number of migrations to apply"
        )

        down_p = subparsers.add_parser("down", help="Roll back latest migration")
        self._add_action_arguments(down_p)
        down_p.add_argument(
            "--steps", type=int, default=1, help="Number of migrations to roll back"
        )

        status_p = subparsers.add_parser("status", help="Show migration status")
        self._add_action_arguments(status_p)

    @staticmethod
    def _add_action_arguments(subparser: argparse.ArgumentParser) -> None:
        """Adds common connection arguments to subcommands."""
        subparser.add_argument(
            "--backend",
            choices=["pydb", "sqlite"],
            default=argparse.SUPPRESS,
            help="Target database engine: 'pydb' (Primary) or 'sqlite' (Secondary).",
        )
        subparser.add_argument(
            "--db-path", default=argparse.SUPPRESS, help="Path to database file"
        )
        subparser.add_argument(
            "--migrations-dir",
            default=argparse.SUPPRESS,
            help="Custom migrations directory",
        )

    def handle(self, args: argparse.Namespace) -> int:
        """Executes the requested migration subcommand."""
        backend_str = getattr(args, "backend", None) or "pydb"
        try:
            backend_type = BackendType(backend_str)
        except ValueError as ex:
            sys.stderr.write(f"[ERROR] Invalid backend '{backend_str}': {ex}\n")
            return 2

        resolved_db = _resolve_target_db(args, backend_type, self.workspace_dir)
        resolved_dir = _resolve_migrations_dir(args, self.workspace_dir)
        return _run_with_manager(resolved_db, resolved_dir, backend_type, args)
