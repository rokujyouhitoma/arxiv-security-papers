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
from .dbshell import init_mounted_sql_executor


def _inspect_table_summary(engine: Any, tname: str) -> List[Any]:
    """Inspects a single table's catalog metadata and safe count."""
    catalog = engine.tables[tname]
    engine_name = catalog.storage.__class__.__name__
    col_count = len(catalog.schema)

    row_count = 0
    try:
        res = engine.execute(f"SELECT COUNT(*) FROM {tname}")
        if res.get("rows"):
            first_val = next(iter(res["rows"][0].values()))
            row_count = int(first_val)
    except Exception:
        row_count = -1

    count_str = str(row_count) if row_count >= 0 else "N/A"
    return [tname, engine_name, col_count, count_str]


class ShowTablesCommand(BaseCommand):
    """Subcommand to list all auto-mounted database tables and metadata."""

    name = "tables"
    help_text = "Display all mounted tables across binary, JSON, and virtual engines."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        pass

    def handle(self, args: argparse.Namespace) -> int:
        engine = init_mounted_sql_executor(self.workspace_dir)
        table_names = sorted(engine.tables.keys())

        if not table_names:
            sys.stdout.write("No database tables are currently mounted.\n")
            return 0

        rows = [_inspect_table_summary(engine, t) for t in table_names]
        headers = ["Table Name", "Storage Engine", "Columns", "Row Count"]
        sys.stdout.write(format_ascii_table(headers, rows) + "\n")
        sys.stdout.write(f"\nTotal: {len(table_names)} tables mounted.\n")
        return 0
