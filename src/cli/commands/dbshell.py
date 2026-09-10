#!/usr/bin/env python3
"""src/cli/commands/dbshell.py

Interactive database shell (dbshell) conforming to DSN-24 Section 4.
Auto-mounts multi-storage engines, provides REPL and one-liner query execution.
Pure Python, zero external dependencies, Xenon CC <= 5.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from typing import List, Optional, Tuple

from database.sql.executor import SQLExecutor
from database.storage.storage import VectorStorage

from ..base import BaseCommand
from ..formatter import format_ascii_table, format_query_result


def _mount_table_safe(engine: SQLExecutor, ddl: str, table_name: str) -> bool:
    """Executes a mount DDL quietly without failing if path does not exist."""
    try:
        engine.execute(ddl)
        return True
    except Exception:
        return False


def _mount_file_plain_text_tables(engine: SQLExecutor, ws: str) -> None:
    """Auto-mounts okf_papers and raw_papers directories as virtual tables."""
    okf_dir = os.path.join(ws, "outputs", "okf_papers")
    if os.path.exists(okf_dir):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS okf_papers ("
            f"id TEXT PRIMARY KEY, title TEXT, description TEXT, tags TEXT, body_markdown TEXT"
            f") USING file_plain_text LOCATION '{okf_dir}'",
            "okf_papers",
        )

    raw_dir = os.path.join(ws, "outputs", "raw_data")
    if os.path.exists(raw_dir):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS raw_papers ("
            f"id TEXT PRIMARY KEY, raw_text TEXT, raw_abstract TEXT"
            f") USING file_plain_text LOCATION '{raw_dir}'",
            "raw_papers",
        )


def _mount_json_tables(engine: SQLExecutor, ws: str) -> None:
    """Auto-mounts JSON and JSONL pipeline states."""
    cat_json = os.path.join(ws, "outputs", "database", "papers_catalog.json")
    if not os.path.exists(cat_json):
        cat_json = os.path.join(ws, "processed_papers.json")
    if os.path.exists(cat_json):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS processed_papers ("
            f"clean_id TEXT PRIMARY KEY, title TEXT, okf_path TEXT, sha256 TEXT"
            f") USING json_table LOCATION '{cat_json}'",
            "processed_papers",
        )

    runs_jsonl = os.path.join(ws, "outputs", "database", "pipeline_state.jsonl")
    if os.path.exists(runs_jsonl):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS pipeline_runs ("
            f"run_id TEXT PRIMARY KEY, timestamp TEXT, phase TEXT, status TEXT"
            f") USING json_lines LOCATION '{runs_jsonl}'",
            "pipeline_runs",
        )


def _mount_vdb_tables(engine: SQLExecutor, ws: str) -> None:
    """Auto-mounts CTI catalog and analytics binary tables."""
    cti_vdb = os.path.join(ws, "outputs", "database", "catalog", "cti_catalog.vdb")
    if os.path.exists(cti_vdb):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS cti_techniques ("
            f"id TEXT PRIMARY KEY, name TEXT, tactics TEXT, description TEXT"
            f") USING binary_vdb LOCATION '{cti_vdb}'",
            "cti_techniques",
        )
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS cisa_kev ("
            f"cve_id TEXT PRIMARY KEY, vendor_project TEXT, vulnerability_name TEXT"
            f") USING binary_vdb LOCATION '{cti_vdb}'",
            "cisa_kev",
        )

    analytics_vdb = os.path.join(
        ws, "outputs", "database", "analytics", "analytics.vdb"
    )
    if os.path.exists(analytics_vdb):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS threat_trends ("
            f"topic_key TEXT PRIMARY KEY, frequency INTEGER, moving_avg_7d REAL"
            f") USING binary_vdb LOCATION '{analytics_vdb}'",
            "threat_trends",
        )


def _mount_knowledge_graph(engine: SQLExecutor, ws: str) -> None:
    kg_vdb = os.path.join(ws, "outputs", "database", "knowledge_graph.vdb")
    if os.path.exists(kg_vdb):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS vertices ("
            f"id TEXT PRIMARY KEY, label TEXT, name TEXT"
            f") USING binary_vdb LOCATION '{kg_vdb}'",
            "vertices",
        )
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS edges ("
            f"id TEXT PRIMARY KEY, source TEXT, target TEXT, relation TEXT"
            f") USING binary_vdb LOCATION '{kg_vdb}'",
            "edges",
        )


def init_mounted_sql_executor(workspace_dir: Optional[str] = None) -> SQLExecutor:
    """Initializes SQLExecutor and auto-mounts all existing workspace tables."""
    ws = os.path.realpath(
        os.path.abspath(workspace_dir or os.environ.get("WORKSPACE_DIR", os.getcwd()))
    )
    executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
    _mount_file_plain_text_tables(executor, ws)
    _mount_json_tables(executor, ws)
    _mount_vdb_tables(executor, ws)
    _mount_knowledge_graph(executor, ws)
    return executor


def _handle_sync_meta(engine: SQLExecutor, ws: str) -> None:
    """Synchronizes physical storage and remounts catalog in executor."""
    from .dbsync import synchronize_database_catalog

    sys.stdout.write("Synchronizing database catalog with physical storage...\n")
    added, total = synchronize_database_catalog(ws)
    if added > 0:
        sys.stdout.write(f"Complemented {added} new record(s). Total: {total}\n")
        _mount_json_tables(engine, ws)
    else:
        sys.stdout.write(f"Already synchronized. Total: {total}\n")


def _meta_tables(engine: SQLExecutor, _parts: List[str], _ws: str) -> None:
    tables = sorted(engine.tables.keys())
    rows = [[t, engine.tables[t].storage.__class__.__name__] for t in tables]
    sys.stdout.write(format_ascii_table(["Table Name", "Storage Engine"], rows) + "\n")


def _meta_schema(engine: SQLExecutor, parts: List[str], _ws: str) -> None:
    tname = parts[1] if len(parts) > 1 else None
    if not tname or tname not in engine.tables:
        sys.stdout.write(
            f"Usage: .schema <table_name>. Known: {list(engine.tables.keys())}\n"
        )
        return
    rows = [[col, str(dt)] for col, dt in engine.tables[tname].schema.items()]
    sys.stdout.write(format_ascii_table(["Column", "Type"], rows) + "\n")


def _meta_help(_engine: SQLExecutor, _parts: List[str], _ws: str) -> None:
    sys.stdout.write(
        "Meta-commands:\n"
        "  .tables             List all auto-mounted tables\n"
        "  .schema <table>     Show column definitions for table\n"
        "  .sync               Synchronize catalog with physical files\n"
        "  .quit / .exit       Exit dbshell\n"
    )


def _execute_meta_command(engine: SQLExecutor, line: str, ws: str) -> bool:
    """Handles dot commands like .tables, .schema, .sync, .help."""
    parts = line.strip().split()
    cmd = parts[0].lower()
    if cmd in (".tables", ".tbl"):
        _meta_tables(engine, parts, ws)
        return True
    if cmd == ".schema":
        _meta_schema(engine, parts, ws)
        return True
    if cmd == ".sync":
        _handle_sync_meta(engine, ws)
        return True
    if cmd == ".help":
        _meta_help(engine, parts, ws)
        return True
    return False


def execute_single_query(engine: SQLExecutor, sql: str) -> int:
    """Executes a single SQL query, formats result table, and prints timing."""
    t0 = time.perf_counter()
    try:
        res = engine.execute(sql)
    except Exception as err:
        sys.stderr.write(f"SQL Error: {err}\n")
        return 1

    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    rows = res.get("rows", [])
    sys.stdout.write(format_query_result(rows) + "\n")
    sys.stdout.write(f"{len(rows)} rows in set ({elapsed_ms:.2f} ms)\n")
    return 0


def _init_readline(engine: SQLExecutor) -> None:
    """Configures readline history and tab autocompletion safely."""
    try:
        import readline

        from ..completer import SQLCompleter

        hist_file = os.path.expanduser("~/.arxiv_dbshell_history")
        if os.path.exists(hist_file):
            readline.read_history_file(hist_file)
        import atexit

        atexit.register(readline.write_history_file, hist_file)

        completer = SQLCompleter(engine)
        readline.set_completer(completer.complete)
        readline.parse_and_bind("tab: complete")
        readline.set_completer_delims(" \t\n;,()")
    except Exception:
        pass


def _prompt_user_input(prompt: str) -> Tuple[bool, Optional[str]]:
    """Prompts for input, catching EOF and KeyboardInterrupt."""
    try:
        return True, input(prompt)
    except EOFError:
        return False, None
    except KeyboardInterrupt:
        sys.stdout.write("\n")
        return True, ""


def _append_and_check_statement(buffer: List[str], line: str) -> Optional[str]:
    stripped = line.strip()
    if not buffer and stripped.startswith("."):
        return stripped
    buffer.append(line)
    if stripped.endswith(";"):
        return " ".join(buffer).strip()
    return None


def _read_full_statement() -> Optional[str]:
    """Reads lines from input until a semicolon or meta-command is found."""
    buffer: List[str] = []
    prompt = "arxiv-sec-db> "
    while True:
        ok, line = _prompt_user_input(prompt)
        if not ok:
            return None
        res = _append_and_check_statement(buffer, line or "")
        if res is not None:
            return res
        prompt = "   ...> "


def _handle_repl_step(engine: SQLExecutor, stmt: str, ws: str) -> bool:
    """Handles single REPL statement. Returns False when session should exit."""
    if stmt in (".quit", ".exit"):
        sys.stdout.write("Goodbye.\n")
        return False
    if stmt.startswith("."):
        _execute_meta_command(engine, stmt, ws)
        return True
    execute_single_query(engine, stmt)
    return True


def run_repl_loop(engine: SQLExecutor, ws: str) -> int:
    """Main interactive REPL loop."""
    _init_readline(engine)
    sys.stdout.write(
        "arXiv Security Papers Database Shell (DSN-24)\n"
        "Auto-mounted tables ready. Press <Tab> for autocomplete, ';' or '.help' for commands.\n"
    )

    while True:
        stmt = _read_full_statement()
        if stmt is None:
            sys.stdout.write("\nGoodbye.\n")
            break
        if not stmt:
            continue
        if not _handle_repl_step(engine, stmt, ws):
            break
    return 0


class DatabaseShellCommand(BaseCommand):
    """Subcommand to launch interactive database shell or run one-liner SQL."""

    name = "dbshell"
    help_text = "Launch interactive SQL shell or execute one-liner query against multi-engine DB."

    def add_arguments(self, parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-c",
            "--command",
            dest="command",
            default=None,
            help="Execute a single SQL command non-interactively and exit.",
        )

    def handle(self, args: argparse.Namespace) -> int:
        ws = self.workspace_dir or os.getcwd()
        engine = init_mounted_sql_executor(ws)
        if args.command:
            return execute_single_query(engine, args.command)
        return run_repl_loop(engine, ws)
