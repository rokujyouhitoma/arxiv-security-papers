#!/usr/bin/env python3
"""src/cli/commands/tables.py

Show tables management subcommand conforming to DSN-24 Section 5.4.
Lists all mounted database tables, storage engine types, and row counts.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, List

from ..base import BaseCommand
from ..formatter import format_ascii_table
from .dbshell import (
    DATABASE_SCOPES,
    detect_table_scope,
    detect_table_type,
    init_mounted_sql_executor,
)


def _safe_table_row_count(engine: Any, catalog: Any, tname: str) -> str:
    """Safely calculates row count without throwing exceptions."""
    try:
        storage = catalog.storage
        if hasattr(storage, "__len__"):
            return str(len(storage))
        if hasattr(storage, "metadata"):
            return str(len(storage.metadata))
        res = engine.execute(f"SELECT COUNT(*) FROM {tname}")
        return str(next(iter(res["rows"][0].values())))
    except Exception:
        return "N/A"


def _inspect_table_summary(engine: Any, tname: str) -> List[Any]:
    """Inspects a single table's catalog metadata, type, and safe count."""
    catalog = engine.tables[tname]
    scope = detect_table_scope(tname)
    ttype = detect_table_type(catalog)
    engine_name = catalog.storage.__class__.__name__
    col_count = len(catalog.schema)
    count_str = _safe_table_row_count(engine, catalog, tname)
    return [tname, scope, ttype, engine_name, col_count, count_str]


class ShowTablesCommand(BaseCommand):
    """Subcommand to list all auto-mounted database tables and metadata."""

    name = "tables"
    help_text = "Display mounted tables across scopes, storage types, and row counts."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-d",
            "--database",
            dest="database",
            default="all",
            choices=list(DATABASE_SCOPES.keys()),
            help="Filter tables by database scope (default: all).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        scope = getattr(args, "database", "all")
        engine = init_mounted_sql_executor(self.workspace_dir, db_scope=scope)
        table_names = sorted(engine.tables.keys())

        if not table_names:
            sys.stdout.write(f"No tables found for database scope '{scope}'.\n")
            return 0

        rows = [_inspect_table_summary(engine, t) for t in table_names]
        headers = [
            "Table Name",
            "Database Scope",
            "Table Type",
            "Storage Engine",
            "Columns",
            "Row Count",
        ]
        sys.stdout.write(format_ascii_table(headers, rows) + "\n")
        sys.stdout.write(
            f"\nTotal: {len(table_names)} tables mounted (Scope: {scope}).\n"
        )
        return 0
