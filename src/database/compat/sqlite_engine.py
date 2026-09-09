#!/usr/bin/env python3
"""
100% Compatible Python Standard `sqlite3` Vector Database Engine.
Provides direct connectivity with `import sqlite3; conn = sqlite3.connect(...)`
with custom Vector UDFs (KNN, COSINE_SIM, EMBED) and bidirectional synchronization
with binary VectorStorage (.vdb) and HNSWIndex.
"""

import json
import os
import re
import sqlite3
from typing import Any, Dict, List, Optional, Tuple

from ..index.embedding import DeterministicEmbedding
from ..storage.multi_storage import MultiTableVectorStorage
from ..storage.storage import VectorStorage


def _parse_vec(v_raw: Any) -> List[float]:
    if isinstance(v_raw, str):
        return [float(x) for x in json.loads(v_raw)]
    return [float(x) for x in v_raw]


def _valid_vecs(v1: List[float], v2: List[float]) -> bool:
    return bool(v1) and bool(v2) and len(v1) == len(v2)


def cosine_sim_udf(v1_raw: Any, v2_raw: Any) -> float:
    """SQLite UDF: Computes cosine similarity between two vectors."""
    try:
        v1 = _parse_vec(v1_raw)
        v2 = _parse_vec(v2_raw)
        if not _valid_vecs(v1, v2):
            return 0.0
        dot = sum(a * b for a, b in zip(v1, v2))
        return float(max(0.0, min(1.0, dot)))
    except Exception:
        return 0.0


def embed_text_udf(text: str) -> str:
    """SQLite UDF: Embeds text string into normalized JSON float array."""
    embedder = DeterministicEmbedding(dim=128)
    vec = embedder.embed_text(text)
    return json.dumps(list(vec))


def register_vector_functions(conn: sqlite3.Connection) -> None:
    """Registers vector functions in standard sqlite3 connection."""
    conn.create_function("COSINE_SIM", 2, cosine_sim_udf)
    conn.create_function("KNN_SCORE", 2, cosine_sim_udf)
    conn.create_function("EMBED", 1, embed_text_udf)


SQLiteConnection = sqlite3.Connection
SQLiteCursor = sqlite3.Cursor
SQLiteRow = sqlite3.Row
SQLiteError = sqlite3.Error
SQLiteOperationalError = sqlite3.OperationalError


def _is_memory_db_path(path: str) -> bool:
    return path in (":memory:", "") or os.path.basename(path) == ":memory:"


def _open_raw_sqlite_connection(
    db_path: str, read_only: bool, timeout: float
) -> sqlite3.Connection:
    if _is_memory_db_path(db_path):
        return sqlite3.connect(":memory:", timeout=timeout)
    abs_path = os.path.abspath(db_path)
    if read_only:
        return sqlite3.connect(f"file:{abs_path}?mode=ro", uri=True, timeout=timeout)
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    return sqlite3.connect(abs_path, timeout=timeout)


def _init_default_table_schema(
    conn: sqlite3.Connection,
    storage: Optional[VectorStorage] = None,
    table_name: str = "records",
    schema_sql: Optional[str] = None,
) -> None:
    cur = conn.cursor()
    if schema_sql:
        cur.executescript(schema_sql)
    else:
        if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", table_name):
            raise ValueError(f"Invalid table identifier: {table_name!r}")
        cur.execute(f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                id TEXT PRIMARY KEY,
                title TEXT,
                description TEXT,
                category TEXT,
                vector TEXT,
                metadata TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """)
    conn.commit()
    if storage and storage.count > 0:
        sync_from_vector_storage(conn, storage, table_name=table_name)


# Backward compatibility alias
_init_papers_schema = _init_default_table_schema


def _configure_wal_pragma(conn: sqlite3.Connection, db_path: str) -> None:
    if not _is_memory_db_path(db_path):
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")


def _setup_connection_features(
    conn: sqlite3.Connection,
    db_path: str,
    storage: Optional[VectorStorage],
    init_schema: bool,
    read_only: bool,
    enable_wal: bool,
    table_name: str,
    schema_sql: Optional[str],
) -> None:
    if read_only:
        return
    if enable_wal:
        _configure_wal_pragma(conn, db_path)
    if init_schema:
        _init_default_table_schema(
            conn,
            storage=storage,
            table_name=table_name,
            schema_sql=schema_sql,
        )


def _is_vdb_container_path(path: str) -> bool:
    return path.endswith(".vdb") and not _is_memory_db_path(path)


def _open_vdb_connection(
    db_path: str, read_only: bool, timeout: float
) -> sqlite3.Connection:
    if _is_memory_db_path(db_path):
        storage = MultiTableVectorStorage(file_path=":memory:")
    else:
        abs_path = os.path.abspath(db_path)
        os.makedirs(os.path.dirname(abs_path), exist_ok=True)
        storage = MultiTableVectorStorage(file_path=abs_path)
        if os.path.exists(abs_path) and os.path.getsize(abs_path) > 0:
            storage.load()
    conn = sqlite3.connect(":memory:", factory=VDBManagedConnection, timeout=timeout)
    conn._vdb_storage = storage
    conn._vdb_read_only = read_only
    sync_from_multi_storage(conn, storage)
    return conn


def get_sqlite_connection(
    db_path: str = ":memory:",
    storage: Optional[VectorStorage] = None,
    init_schema: bool = True,
    read_only: bool = False,
    enable_wal: bool = False,
    timeout: float = 5.0,
    table_name: str = "records",
    schema_sql: Optional[str] = None,
) -> sqlite3.Connection:
    """
    Returns standard `sqlite3.Connection` with full SQLite SQL support and vector UDFs.
    Seamlessly supports binary .vdb container files with automatic synchronization.
    """
    if _is_vdb_container_path(db_path):
        conn = _open_vdb_connection(db_path, read_only, timeout)
    else:
        conn = _open_raw_sqlite_connection(db_path, read_only, timeout)
    try:
        conn.row_factory = sqlite3.Row
        register_vector_functions(conn)
        _setup_connection_features(
            conn,
            db_path=db_path,
            storage=storage,
            init_schema=init_schema,
            read_only=read_only,
            enable_wal=enable_wal,
            table_name=table_name,
            schema_sql=schema_sql,
        )
        return conn
    except Exception:
        conn.close()
        raise


def get_sqlite_table_names(conn: sqlite3.Connection) -> List[str]:
    """Returns a list of all user table names in the SQLite database."""
    cur = conn.cursor()
    cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )
    return [str(row[0]) for row in cur.fetchall()]


def _count_table_rows(cur: sqlite3.Cursor, tbl: str) -> int:
    if not tbl.isidentifier():
        return 0
    cur.execute(f"SELECT COUNT(*) FROM {tbl}")
    r = cur.fetchone()
    return int(r[0]) if r else 0


def sum_sqlite_table_rows(conn: sqlite3.Connection) -> Optional[int]:
    """Calculates the sum of row counts across all user tables in the database."""
    cur = conn.cursor()
    total = sum(_count_table_rows(cur, tbl) for tbl in get_sqlite_table_names(conn))
    return total if total > 0 else None


def count_sqlite_table_rows(db_path: str) -> Optional[int]:
    """Safely opens an SQLite database in read-only mode and returns the total row count."""
    if not os.path.exists(db_path):
        return None
    try:
        conn = get_sqlite_connection(db_path, init_schema=False, read_only=True)
        try:
            return sum_sqlite_table_rows(conn)
        finally:
            conn.close()
    except Exception:
        return None


def _query_counts_on_connection(
    conn: sqlite3.Connection, targets: Optional[List[str]]
) -> Dict[str, int]:
    cur = conn.cursor()
    names = targets if targets is not None else get_sqlite_table_names(conn)
    return {t: _count_table_rows(cur, t) for t in names}


def _safe_connect_and_query(
    db_path: str, targets: Optional[List[str]]
) -> Optional[Dict[str, int]]:
    conn = get_sqlite_connection(db_path, init_schema=False, read_only=True)
    try:
        return _query_counts_on_connection(conn, targets)
    finally:
        conn.close()


def _fallback_counts(targets: Optional[List[str]]) -> Dict[str, int]:
    return {t: 0 for t in (targets or [])}


def _resolve_vdb_target_names(
    storage: MultiTableVectorStorage, targets: Optional[List[str]]
) -> List[str]:
    if targets is not None:
        return targets
    return [t for t in storage.list_tables() if t != "_schemas"]


def _read_table_counts_from_storage(
    storage: MultiTableVectorStorage, targets: Optional[List[str]]
) -> Dict[str, int]:
    names = _resolve_vdb_target_names(storage, targets)
    return {t: storage.get_table(t).count for t in names if storage.has_table(t)}


def _get_vdb_table_counts(db_path: str, targets: Optional[List[str]]) -> Dict[str, int]:
    abs_path = os.path.abspath(db_path)
    if not os.path.exists(abs_path) or os.path.getsize(abs_path) == 0:
        return _fallback_counts(targets)
    try:
        storage = MultiTableVectorStorage(file_path=abs_path)
        storage.load()
        return _read_table_counts_from_storage(storage, targets)
    except Exception:
        return _fallback_counts(targets)


def get_sqlite_table_counts(
    db_path: str, table_names: Optional[List[str]] = None
) -> Dict[str, int]:
    """Safely queries row counts for specified or all user tables in an SQLite database.

    Domain-agnostic database infrastructure utility.
    """
    if not os.path.exists(db_path):
        return _fallback_counts(table_names)
    if _is_vdb_container_path(db_path):
        return _get_vdb_table_counts(db_path, table_names)
    try:
        res = _safe_connect_and_query(db_path, table_names)
        return res if res else _fallback_counts(table_names)
    except Exception:
        return _fallback_counts(table_names)


def _rows_to_dicts(cur: sqlite3.Cursor, rows: List[Any]) -> List[Dict[str, Any]]:
    col_names = [col[0] for col in cur.description] if cur.description else []
    return [dict(zip(col_names, row)) for row in rows]


def dump_sqlite_table_records(
    conn: sqlite3.Connection, table_name: str
) -> List[Dict[str, Any]]:
    """Dumps all rows of an arbitrary table into a list of dictionaries.

    Domain-agnostic database migration utility.
    """
    if not table_name.isidentifier():
        return []
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM {table_name}")
    rows = cur.fetchall()
    return _rows_to_dicts(cur, rows) if rows else []


def _execute_restore_batch(
    cur: sqlite3.Cursor, table_name: str, keys: List[str], records: List[Dict[str, Any]]
) -> int:
    cols = ", ".join(keys)
    placeholders = ", ".join(["?" for _ in keys])
    sql = f"INSERT OR REPLACE INTO {table_name} ({cols}) VALUES ({placeholders})"
    tuples = [tuple(r.get(k) for k in keys) for r in records]
    cur.executemany(sql, tuples)
    return len(records)


def restore_sqlite_table_records(
    conn: sqlite3.Connection, table_name: str, records: List[Dict[str, Any]]
) -> int:
    """Restores a list of row dictionaries into a table using INSERT OR REPLACE.

    Domain-agnostic database migration utility.
    """
    if not records or not table_name.isidentifier():
        return 0
    keys = list(records[0].keys())
    if not all(k.isidentifier() for k in keys):
        return 0
    cur = conn.cursor()
    inserted = _execute_restore_batch(cur, table_name, keys, records)
    conn.commit()
    return inserted


def sync_from_vector_storage(
    conn: sqlite3.Connection, storage: VectorStorage, table_name: str = "records"
) -> int:
    """Synchronizes records from binary VectorStorage into SQLite table."""
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", table_name):
        raise ValueError(f"Invalid table identifier: {table_name!r}")
    records = []
    for idx in range(storage.count):
        meta = storage.get_metadata(idx)
        vec = list(storage.get_vector(idx))
        doc_id = str(meta.get("id", str(idx)))
        title = str(meta.get("title", ""))
        desc = str(meta.get("description", ""))
        cat = str(meta.get("category", ""))
        records.append(
            (
                doc_id,
                title,
                desc,
                cat,
                json.dumps(vec),
                json.dumps(meta, ensure_ascii=False),
            )
        )

    cur = conn.cursor()
    cur.executemany(
        f"""
        INSERT OR REPLACE INTO {table_name} (id, title, description, category, vector, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        records,
    )
    conn.commit()
    return len(records)


def sync_to_vector_storage(
    conn: sqlite3.Connection, storage: VectorStorage, table_name: str = "records"
) -> int:
    """Synchronizes records from SQLite table back into binary VectorStorage (.vdb)."""
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", table_name):
        raise ValueError(f"Invalid table identifier: {table_name!r}")
    cur = conn.cursor()
    cur.execute(f"SELECT id, vector, metadata FROM {table_name} ORDER BY id ASC")
    rows = cur.fetchall()

    vectors: List[Tuple[float, ...]] = []
    metadata: List[Dict[str, Any]] = []

    for r in rows:
        vec_list = json.loads(r["vector"]) if r["vector"] else [0.0] * storage.dim
        meta_dict = json.loads(r["metadata"]) if r["metadata"] else {}
        meta_dict.setdefault("id", str(r["id"]))
        vectors.append(tuple(vec_list))
        metadata.append(meta_dict)

    storage.write_all(vectors, metadata)
    return len(vectors)


class VDBManagedConnection(sqlite3.Connection):
    """SQLite connection automatically synchronized with a MultiTableVectorStorage (.vdb)."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._vdb_storage: Optional[MultiTableVectorStorage] = None
        self._vdb_read_only: bool = False

    def sync_to_vdb(self) -> None:
        if self._vdb_storage is not None and not self._vdb_read_only:
            sync_to_multi_storage(self, self._vdb_storage)

    def commit(self) -> None:
        super().commit()
        self.sync_to_vdb()

    def close(self) -> None:
        try:
            self.sync_to_vdb()
        finally:
            super().close()


def _create_table_from_meta_if_missing(
    conn: sqlite3.Connection, tbl_name: str, meta: List[Dict[str, Any]]
) -> None:
    if not meta:
        return
    first = meta[0]
    cols = ", ".join(f"{k} TEXT" for k in first.keys() if k.isidentifier())
    conn.execute(f"CREATE TABLE IF NOT EXISTS {tbl_name} ({cols})")


def _restore_single_multi_table(
    conn: sqlite3.Connection,
    tbl_name: str,
    v_tbl: VectorStorage,
    schema_sql: Optional[str],
) -> None:
    if schema_sql:
        conn.execute(schema_sql)
    else:
        _create_table_from_meta_if_missing(conn, tbl_name, v_tbl.metadata)
    if v_tbl.metadata:
        restore_sqlite_table_records(conn, tbl_name, v_tbl.metadata)


def _parse_schema_record(row: Any) -> Optional[Tuple[str, str]]:
    if isinstance(row, dict) and "table_name" in row and "sql" in row:
        return str(row["table_name"]), str(row["sql"])
    return None


def _load_schemas_from_storage(storage: MultiTableVectorStorage) -> Dict[str, str]:
    if not storage.has_table("_schemas"):
        return {}
    res: Dict[str, str] = {}
    for row in storage.get_table("_schemas").metadata:
        item = _parse_schema_record(row)
        if item:
            res[item[0]] = item[1]
    return res


def sync_from_multi_storage(
    conn: sqlite3.Connection,
    storage: MultiTableVectorStorage,
) -> Dict[str, int]:
    """Restores all tables and schemas from MultiTableVectorStorage into an SQLite connection."""
    schema_map = _load_schemas_from_storage(storage)
    restored_counts: Dict[str, int] = {}
    for tbl_name in storage.list_tables():
        if tbl_name == "_schemas":
            continue
        v_tbl = storage.get_table(tbl_name)
        _restore_single_multi_table(conn, tbl_name, v_tbl, schema_map.get(tbl_name))
        restored_counts[tbl_name] = v_tbl.count
    conn.commit()
    return restored_counts


def _save_table_to_storage(
    storage: MultiTableVectorStorage, tbl: str, recs: List[Dict[str, Any]]
) -> None:
    t = (
        storage.get_table(tbl)
        if storage.has_table(tbl)
        else storage.create_table(tbl, dim=4)
    )
    v = [(0.0, 0.0, 0.0, 0.0)] * len(recs)
    t.write_all(v, recs)


def _get_savable_tables(conn: sqlite3.Connection) -> List[str]:
    return [
        t
        for t in get_sqlite_table_names(conn)
        if not t.endswith("_fts") and "_fts_" not in t and t != "_schemas"
    ]


def _build_ddl_records(
    conn: sqlite3.Connection, tables: List[str]
) -> List[Dict[str, Any]]:
    cur = conn.cursor()
    cur.execute("SELECT name, sql FROM sqlite_master WHERE type='table'")
    schema_rows = cur.fetchall()
    return [
        {"table_name": str(r[0]), "sql": str(r[1])}
        for r in schema_rows
        if r[0] in tables and r[1]
    ]


def sync_to_multi_storage(
    conn: sqlite3.Connection,
    storage: MultiTableVectorStorage,
) -> Dict[str, int]:
    """Dumps user tables from SQLite connection and commits to MultiTableVectorStorage (.vdb)."""
    user_tables = _get_savable_tables(conn)
    ddl_records = _build_ddl_records(conn, user_tables)
    _save_table_to_storage(storage, "_schemas", ddl_records)

    counts: Dict[str, int] = {}
    for tbl in user_tables:
        recs = dump_sqlite_table_records(conn, tbl)
        _save_table_to_storage(storage, tbl, recs)
        counts[tbl] = len(recs)

    storage.save()
    return counts
