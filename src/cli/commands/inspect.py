#!/usr/bin/env python3
"""src/cli/commands/inspect.py

Table inspector subcommand conforming to DSN-24 Section 5.4.
Displays detailed schema columns, types, and head sample records of a target table.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any

from ..base import BaseCommand
from ..formatter import format_ascii_table, format_query_result
from .dbshell import init_mounted_sql_executor


def _print_table_schema(catalog: Any, tname: str) -> None:
    """Renders table schema columns and data types."""
    engine_name = catalog.storage.__class__.__name__
    sys.stdout.write(f"\nTable: {tname} (Engine: {engine_name})\n")
    schema_rows = [[col, str(dt)] for col, dt in catalog.schema.items()]
    sys.stdout.write(
        format_ascii_table(["Column Name", "Data Type"], schema_rows) + "\n"
    )


def _print_sample_rows(engine: Any, tname: str, limit: int) -> None:
    """Queries and renders head sample records."""
    sys.stdout.write(f"\nHead Sample ({limit} rows):\n")
    try:
        res = engine.execute(f"SELECT * FROM {tname} LIMIT {limit}")
        rows = res.get("rows", [])
        sys.stdout.write(format_query_result(rows) + "\n")
    except Exception as err:
        sys.stdout.write(f"(Failed to retrieve sample rows: {err})\n")


class InspectTableCommand(BaseCommand):
    """Subcommand to inspect table schema and sample data."""

    name = "inspect"
    help_text = (
        "Inspect schema definition and sample rows of a specific database table."
    )

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument("table", help="Name of the table to inspect.")
        parser.add_argument(
            "-n",
            "--limit",
            dest="limit",
            type=int,
            default=3,
            help="Number of sample rows to display (default: 3).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        engine = init_mounted_sql_executor(self.workspace_dir)
        tname = args.table

        if tname not in engine.tables:
            known = ", ".join(sorted(engine.tables.keys()))
            sys.stderr.write(
                f"Table '{tname}' not found. Available tables: [{known}]\n"
            )
            return 1

        catalog = engine.tables[tname]
        _print_table_schema(catalog, tname)
        _print_sample_rows(engine, tname, max(1, args.limit))
        return 0
