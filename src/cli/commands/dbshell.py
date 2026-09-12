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
from typing import Any, Dict, List, Optional, Tuple

from database.sql.executor import SQLExecutor, TableCatalog, _extract_pk_col
from database.storage.storage import VectorStorage
from settings import (
    BASE_DIR,
    DATABASES,
    get_database_scopes,
    get_table_scope_from_settings,
    get_table_type_from_settings,
)

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
            f"clean_id VARCHAR(64) PRIMARY KEY, "
            f"arxiv_id VARCHAR(32), "
            f"title TEXT, "
            f"title_ja TEXT, "
            f"description TEXT, "
            f"tags JSON, "
            f"published_date TIMESTAMP, "
            f"timestamp TIMESTAMP, "
            f"resource VARCHAR(256), "
            f"file_size_bytes INTEGER, "
            f"updated_at TIMESTAMP, "
            f"body_markdown TEXT"
            f") USING file_plain_text LOCATION '{okf_dir}'",
            "okf_papers",
        )

    raw_dir = os.path.join(ws, "outputs", "raw_data")
    if os.path.exists(raw_dir):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS raw_papers ("
            f"clean_id VARCHAR(64) PRIMARY KEY, "
            f"arxiv_id VARCHAR(32), "
            f"file_path VARCHAR(256), "
            f"file_size_bytes INTEGER, "
            f"updated_at TIMESTAMP, "
            f"raw_abstract TEXT, "
            f"raw_text TEXT"
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
            f"clean_id VARCHAR(64) PRIMARY KEY, "
            f"title TEXT, "
            f"title_ja TEXT, "
            f"processed_at TIMESTAMP, "
            f"published TIMESTAMP, "
            f"okf_path VARCHAR(256), "
            f"raw_meta_path VARCHAR(256), "
            f"sha256 VARCHAR(64)"
            f") USING json_table LOCATION '{cat_json}'",
            "processed_papers",
        )

    runs_jsonl = os.path.join(ws, "outputs", "database", "pipeline_state.jsonl")
    if os.path.exists(runs_jsonl):
        _mount_table_safe(
            engine,
            f"CREATE TABLE IF NOT EXISTS pipeline_runs ("
            f"run_id VARCHAR(64) PRIMARY KEY, "
            f"timestamp TIMESTAMP, "
            f"phase VARCHAR(32), "
            f"status VARCHAR(32), "
            f"records_collected INTEGER, "
            f"records_processed INTEGER, "
            f"products_published INTEGER"
            f") USING json_lines LOCATION '{runs_jsonl}'",
            "pipeline_runs",
        )


DATABASE_SCOPES: Dict[str, str] = get_database_scopes()


def _find_sql_in_metadata(metadata: List[Any], tname: str) -> Optional[str]:
    for row in metadata:
        if isinstance(row, dict) and row.get("table_name") == tname:
            sql = row.get("sql")
            if sql:
                return str(sql)
    return None


def _lookup_container_schema_sql(container: Any, tname: str) -> Optional[str]:
    """Looks up saved CREATE TABLE DDL from _schemas table if present."""
    if (
        not hasattr(container, "list_tables")
        or "_schemas" not in container.list_tables()
    ):
        return None
    try:
        tbl = container.get_table("_schemas")
        return _find_sql_in_metadata(getattr(tbl, "metadata", []), tname)
    except Exception:
        return None


def _is_json_like(val: Any) -> bool:
    if isinstance(val, (dict, list)):
        return True
    return isinstance(val, str) and (val.startswith("{") or val.startswith("["))


def _infer_value_sql_type(val: Any) -> str:
    """Infers SQL data type from a Python value."""
    if isinstance(val, bool):
        return "BOOLEAN"
    if isinstance(val, int):
        return "INTEGER"
    if isinstance(val, float):
        return "FLOAT"
    return "JSON" if _is_json_like(val) else "VARCHAR(256)"


def _infer_column_type(col_name: str, val: Any) -> str:
    if col_name == "id" or col_name.endswith("_id"):
        return "VARCHAR(64)"
    return _infer_value_sql_type(val)


def _infer_table_schema(storage: Any) -> Dict[str, str]:
    """Infers column schema from the first metadata record in storage."""
    metadata = getattr(storage, "metadata", [])
    if not (metadata and isinstance(metadata, list) and isinstance(metadata[0], dict)):
        return {"id": "VARCHAR(64)", "metadata": "JSON"}

    first_row: Dict[str, Any] = metadata[0]
    return {col: _infer_column_type(col, val) for col, val in first_row.items()}


def _resolve_container_table_ddl(
    container: Any, tname: str, storage: Any, file_path: str
) -> Tuple[Dict[str, str], str]:
    """Resolves table schema and DDL, either from _schemas or inferred from metadata."""
    saved_sql = _lookup_container_schema_sql(container, tname)
    if saved_sql:
        return {"id": "VARCHAR(64)", "metadata": "JSON"}, saved_sql

    schema = _infer_table_schema(storage)
    cols_def = ", ".join(f"{col} {dtype}" for col, dtype in schema.items())
    inferred_ddl = (
        f"-- Inferred from storage metadata\n"
        f"CREATE TABLE IF NOT EXISTS {tname} ({cols_def}) "
        f"USING binary_vdb LOCATION '{file_path}'"
    )
    return schema, inferred_ddl


def _mount_single_container_table(
    engine: SQLExecutor, tname: str, container: Any, file_path: str, scope: str
) -> None:
    if tname.startswith("_") or tname in engine.tables:
        return
    storage = container.get_table(tname)
    schema, ddl = _resolve_container_table_ddl(container, tname, storage, file_path)
    catalog = TableCatalog(
        name=tname,
        storage=storage,
        schema=schema,
        raw_sql=ddl,
        storage_engine="MultiTableVectorStorage",
        location=file_path,
        database_scope=scope,
    )
    engine.tables[tname] = catalog


def _mount_multitable_container(
    engine: SQLExecutor, file_path: str, scope: str
) -> None:
    """Auto-mounts all named tables from a MultiTableVectorStorage container."""
    if not os.path.exists(file_path):
        return
    try:
        from database.storage.multi_storage import MultiTableVectorStorage

        container = MultiTableVectorStorage(file_path)
        for tname in container.list_tables():
            _mount_single_container_table(engine, tname, container, file_path, scope)
    except Exception:
        pass


def detect_table_scope(tname: str) -> str:
    """Classifies a table into its corresponding logical database scope."""
    return get_table_scope_from_settings(tname)


def _is_markdown_patterns(patterns: List[str]) -> bool:
    has_md = any("md" in p for p in patterns)
    has_txt = any("txt" in p for p in patterns)
    return has_md and not has_txt


def _detect_plain_text_type(catalog: Any, storage: Any) -> str:
    if getattr(catalog, "name", "") == "okf_papers":
        return "Virtual (Markdown)"
    if _is_markdown_patterns(getattr(storage, "patterns", [])):
        return "Virtual (Markdown)"
    return "Virtual (Text)"


def _detect_virtual_type(catalog: Any, storage: Any) -> Optional[str]:
    st_name = storage.__class__.__name__
    if st_name == "FileBackedPlainTextStorage":
        return _detect_plain_text_type(catalog, storage)
    if st_name == "JsonTableStorage":
        return "Virtual (JSON)"
    if st_name == "JsonLinesStorage":
        return "Virtual (JSONL)"
    if st_name == "CsvTableStorage":
        return "Virtual (CSV)"
    return None


def _detect_physical_or_memory_type(catalog: Any, storage: Any) -> str:
    loc = getattr(catalog, "location", "") or getattr(storage, "file_path", "")
    if loc and loc not in (":memory:", ""):
        return "Physical (VDB)"
    return "In-Memory"


def detect_table_type(catalog: Any) -> str:
    """Detects whether a table is a Virtual Table, Physical VDB, or In-Memory."""
    tname = getattr(catalog, "name", "")
    declared = get_table_type_from_settings(tname)
    if declared:
        return declared
    storage = getattr(catalog, "storage", catalog)
    v_type = _detect_virtual_type(catalog, storage)
    return v_type if v_type else _detect_physical_or_memory_type(catalog, storage)


def _mount_single_csv_table(
    engine: SQLExecutor, ws: str, s_name: str, tname: str, tcfg: Dict[str, Any]
) -> None:
    loc = tcfg.get("LOCATION")
    if not loc:
        return
    rel = os.path.relpath(loc, BASE_DIR)
    target_path = os.path.join(ws, rel)
    if not os.path.exists(target_path):
        return
    pk = tcfg.get("PRIMARY_KEY", "id")
    from database.storage.factory import StorageEngineFactory

    storage = StorageEngineFactory.create_by_engine_name(
        "csv_table", location=target_path, primary_key=pk
    )
    schema = _infer_table_schema(storage)
    cols_def = ", ".join(f"{col} {dtype}" for col, dtype in schema.items())
    ddl = (
        f"-- Inferred from CSV metadata\n"
        f"CREATE TABLE IF NOT EXISTS {tname} ({cols_def}) "
        f"USING csv_table LOCATION '{target_path}'"
    )
    catalog = TableCatalog(
        name=tname,
        storage=storage,
        schema=schema,
        raw_sql=ddl,
        storage_engine="CsvTableStorage",
        location=target_path,
        database_scope=s_name,
    )
    engine.tables[tname] = catalog


def _mount_configured_csv_tables(
    engine: SQLExecutor, ws: str, s_name: str, cfg: Dict[str, Any]
) -> None:
    tables_cfg = cfg.get("TABLES", {})
    for tname, tcfg in tables_cfg.items():
        if tcfg.get("ENGINE") == "csv_table":
            _mount_single_csv_table(engine, ws, s_name, tname, tcfg)


def _mount_single_configured_scope(engine: SQLExecutor, ws: str, s_name: str) -> None:
    cfg = DATABASES.get(s_name, {})
    _mount_configured_csv_tables(engine, ws, s_name, cfg)
    loc = cfg.get("LOCATION")
    if loc:
        rel = os.path.relpath(loc, BASE_DIR)
        target_path = os.path.join(ws, rel)
        _mount_multitable_container(engine, target_path, s_name)


def _mount_scope_tables(engine: SQLExecutor, ws: str, scope: str) -> None:
    if scope in ("all", "arxiv_security_db"):
        _mount_file_plain_text_tables(engine, ws)
        _mount_json_tables(engine, ws)
    for s_name in ("cti_catalog_db", "analytics_db", "graph_db"):
        if scope in ("all", s_name):
            _mount_single_configured_scope(engine, ws, s_name)


def init_mounted_sql_executor(
    workspace_dir: Optional[str] = None,
    db_scope: Optional[str] = "all",
) -> SQLExecutor:
    """Initializes SQLExecutor and auto-mounts tables for the given database scope."""
    ws = os.path.realpath(
        os.path.abspath(workspace_dir or os.environ.get("WORKSPACE_DIR", os.getcwd()))
    )
    executor = SQLExecutor(default_storage=VectorStorage(":memory:", dim=4))
    if "main" in executor.tables:
        executor.tables["main"].schema = {
            "id": "VARCHAR(64)",
            "vector": "VECTOR(4)",
            "metadata": "JSON",
        }
    _mount_scope_tables(executor, ws, db_scope or "all")
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


class DBShellSession:
    """Manages dbshell interactive session state and active database scope."""

    def __init__(
        self,
        engine: SQLExecutor,
        ws: str,
        initial_scope: str = "all",
    ) -> None:
        self.engine = engine
        self.ws = ws
        self.scope = initial_scope

    def switch_scope(self, target: str) -> bool:
        clean = target.rstrip(";").strip()
        if clean not in DATABASE_SCOPES:
            valid = ", ".join(sorted(DATABASE_SCOPES.keys()))
            sys.stdout.write(f"Unknown scope: '{clean}'. Available: [{valid}]\n")
            return False
        self.scope = clean
        sys.stdout.write(f"Switched database scope to '{clean}'.\n")
        return True

    def get_prompt(self) -> str:
        if self.scope == "all":
            return "arxiv-sec-db> "
        return f"arxiv-sec-db [{self.scope}]> "


def _format_table_row(engine: SQLExecutor, t: str) -> List[Any]:
    cat = engine.tables[t]
    return [
        t,
        detect_table_scope(t),
        detect_table_type(cat),
        cat.storage.__class__.__name__,
    ]


def _filter_tables_by_scope(tables: List[str], target: Optional[str]) -> List[str]:
    if not target or target == "all":
        return tables
    return [t for t in tables if detect_table_scope(t) in (target, "default")]


def _meta_tables(
    engine: SQLExecutor, parts: List[str], active_scope: str = "all"
) -> None:
    target_scope = parts[1] if len(parts) > 1 else active_scope
    tables = _filter_tables_by_scope(sorted(engine.tables.keys()), target_scope)
    if not tables:
        sys.stdout.write(f"No tables found for scope '{target_scope}'.\n")
        return
    rows = [_format_table_row(engine, t) for t in tables]
    headers = ["Table Name", "Database Scope", "Table Type", "Storage Engine"]
    sys.stdout.write(format_ascii_table(headers, rows) + "\n")


def _scope_row(
    engine: SQLExecutor, active_scope: str, s_name: str, desc: str
) -> List[Any]:
    prefix = "* " if s_name == active_scope else "  "
    if s_name == "all":
        cnt = len(engine.tables)
    else:
        cnt = sum(1 for t in engine.tables if detect_table_scope(t) == s_name)
    return [f"{prefix}{s_name}", cnt, desc]


def _meta_databases(engine: SQLExecutor, active_scope: str) -> None:
    rows = [_scope_row(engine, active_scope, s, d) for s, d in DATABASE_SCOPES.items()]
    headers = ["Database Scope", "Tables", "Description"]
    sys.stdout.write(format_ascii_table(headers, rows) + "\n")


def _print_single_table_ddl(engine: SQLExecutor, tname: str) -> None:
    catalog = engine.tables[tname]
    sys.stdout.write(f"{catalog.get_ddl()}\n")
    for idx_ddl in catalog.get_index_ddls():
        sys.stdout.write(f"{idx_ddl}\n")


def _meta_schema(engine: SQLExecutor, parts: List[str], _ws: str) -> None:
    """Displays DDL statements (CREATE TABLE & CREATE INDEX) or column schema."""
    tname = parts[1] if len(parts) > 1 else None
    if tname:
        if tname not in engine.tables:
            sys.stdout.write(
                f"Table '{tname}' not found. Known: {list(engine.tables.keys())}\n"
            )
            return
        _print_single_table_ddl(engine, tname)
        return

    for t in sorted(engine.tables.keys()):
        _print_single_table_ddl(engine, t)
        sys.stdout.write("\n")


def _format_index_row(defn: Dict[str, str], tname: str) -> List[Any]:
    return [
        tname,
        defn.get("name", "idx"),
        defn.get("type", "INDEX"),
        defn.get("column", "*"),
    ]


def _should_append_vector_idx(cat: Any) -> bool:
    has_dim = getattr(getattr(cat, "index", None), "dim", 0) > 0
    if not has_dim:
        return False
    defs = getattr(cat, "index_definitions", [])
    return not any(d.get("type") == "HNSW" for d in defs)


def _prepend_pk_idx(cat: Any, tname: str, rows: List[List[Any]]) -> None:
    defs = getattr(cat, "index_definitions", [])
    pk = _extract_pk_col(getattr(cat, "raw_sql", ""))
    if pk and not any(d.get("column") == pk for d in defs):
        rows.insert(0, [tname, f"pk_{tname}_{pk}", "UNIQUE BTREE", pk])


def _table_index_rows(cat: Any, tname: str) -> List[List[Any]]:
    defs = getattr(cat, "index_definitions", [])
    rows = [_format_index_row(d, tname) for d in defs]
    _prepend_pk_idx(cat, tname, rows)
    if _should_append_vector_idx(cat):
        rows.append([tname, f"idx_{tname}_vector", "HNSW", "vector"])
    return rows


def _collect_all_indexes(engine: SQLExecutor, tname: Optional[str]) -> List[List[Any]]:
    tables = (
        [tname] if (tname and tname in engine.tables) else sorted(engine.tables.keys())
    )
    res: List[List[Any]] = []
    for t in tables:
        res.extend(_table_index_rows(engine.tables[t], t))
    return res


def _meta_indexes(engine: SQLExecutor, parts: List[str], _ws: str) -> None:
    """Displays active indexes across tables or for a specific table."""
    tname = parts[1] if len(parts) > 1 else None
    if tname and tname not in engine.tables:
        sys.stdout.write(
            f"Table '{tname}' not found. Known: {list(engine.tables.keys())}\n"
        )
        return
    rows = _collect_all_indexes(engine, tname)
    if not rows:
        sys.stdout.write("No active indexes found.\n")
        return
    headers = ["Table Name", "Index Name", "Index Type", "Target Column"]
    sys.stdout.write(format_ascii_table(headers, rows) + "\n")


def _meta_help(_engine: SQLExecutor, _parts: List[str], _ws: str) -> None:
    sys.stdout.write(
        "Meta-commands:\n"
        "  .databases          List available database scopes and active scope (*)\n"
        "  .use <database>     Switch active scope (e.g. .use cti_catalog_db)\n"
        "  .tables [scope]     List mounted tables (with Table Type & Scope)\n"
        "  .schema [table]     Show CREATE TABLE and CREATE INDEX DDL\n"
        "  .indexes [table]    List active indexes (HNSW / BTREE)\n"
        "  .sync               Synchronize catalog with physical files\n"
        "  .quit / .exit       Exit dbshell\n"
    )


def _handle_use_meta(session: DBShellSession, parts: List[str]) -> None:
    if len(parts) > 1:
        session.switch_scope(parts[1])
    else:
        sys.stdout.write("Usage: .use <database_scope>\n")


def _dispatch_db_meta(session: DBShellSession, cmd: str, parts: List[str]) -> bool:
    if cmd in (".tables", ".tbl"):
        _meta_tables(session.engine, parts, session.scope)
        return True
    if cmd in (".databases", ".dbs"):
        _meta_databases(session.engine, session.scope)
        return True
    if cmd == ".use":
        _handle_use_meta(session, parts)
        return True
    return False


def _dispatch_schema_meta(session: DBShellSession, cmd: str, parts: List[str]) -> bool:
    if cmd == ".schema":
        _meta_schema(session.engine, parts, session.ws)
        return True
    if cmd in (".indexes", ".indices"):
        _meta_indexes(session.engine, parts, session.ws)
        return True
    if cmd == ".sync":
        _handle_sync_meta(session.engine, session.ws)
        return True
    if cmd == ".help":
        _meta_help(session.engine, parts, session.ws)
        return True
    return False


def _execute_meta_command(session: DBShellSession, line: str) -> bool:
    """Handles dot commands like .tables, .schema, .indexes, .databases, .use, .sync, .help."""
    parts = line.strip().split()
    cmd = parts[0].lower()
    return _dispatch_db_meta(session, cmd, parts) or _dispatch_schema_meta(
        session, cmd, parts
    )


def _resolve_session_instance(
    engine_or_session: Any, ws: Optional[str]
) -> DBShellSession:
    if isinstance(engine_or_session, DBShellSession):
        return engine_or_session
    return DBShellSession(engine_or_session, ws or os.getcwd(), "all")


def execute_single_query(
    engine_or_session: Any, sql: str, ws: Optional[str] = None
) -> int:
    """Executes a single SQL query or meta-command, formats result table, and prints timing."""
    session = _resolve_session_instance(engine_or_session, ws)
    clean = sql.strip()
    if clean.startswith("."):
        _execute_meta_command(session, clean)
        return 0
    if clean.upper().startswith("USE "):
        parts = clean.split()
        if len(parts) >= 2:
            session.switch_scope(parts[1])
            return 0

    t0 = time.perf_counter()
    try:
        res = session.engine.execute(sql)
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


def _read_full_statement(initial_prompt: str = "arxiv-sec-db> ") -> Optional[str]:
    """Reads lines from input until a semicolon or meta-command is found."""
    buffer: List[str] = []
    prompt = initial_prompt
    while True:
        ok, line = _prompt_user_input(prompt)
        if not ok:
            return None
        res = _append_and_check_statement(buffer, line or "")
        if res is not None:
            return res
        prompt = "   ...> "


def _handle_repl_step(session: DBShellSession, stmt: str) -> bool:
    """Handles single REPL statement. Returns False when session should exit."""
    clean = stmt.strip()
    if clean in (".quit", ".exit"):
        sys.stdout.write("Goodbye.\n")
        return False
    if clean.startswith("."):
        _execute_meta_command(session, clean)
        return True
    if clean.upper().startswith("USE "):
        parts = clean.split()
        if len(parts) >= 2:
            session.switch_scope(parts[1])
            return True
    execute_single_query(session, clean)
    return True


def run_repl_loop(engine_or_session: Any, ws: Optional[str] = None) -> int:
    """Main interactive REPL loop."""
    session = _resolve_session_instance(engine_or_session, ws)
    _init_readline(session.engine)
    sys.stdout.write(
        "arXiv Security Papers Database Shell (DSN-24)\n"
        "Auto-mounted tables ready. Press <Tab> for autocomplete, ';' or '.help' for commands.\n"
    )

    while True:
        prompt = session.get_prompt()
        stmt = _read_full_statement(prompt)
        if stmt is None:
            sys.stdout.write("\nGoodbye.\n")
            break
        if not stmt:
            continue
        if not _handle_repl_step(session, stmt):
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
        parser.add_argument(
            "-d",
            "--database",
            dest="database",
            default="all",
            choices=list(DATABASE_SCOPES.keys()),
            help="Initial active database scope (default: all).",
        )

    def handle(self, args: argparse.Namespace) -> int:
        ws = self.workspace_dir or os.getcwd()
        scope = getattr(args, "database", "all")
        engine = init_mounted_sql_executor(ws, db_scope=scope)
        session = DBShellSession(engine, ws, initial_scope=scope)
        if args.command:
            return execute_single_query(session, args.command)
        return run_repl_loop(session)
