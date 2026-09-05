#!/usr/bin/env python3
"""
100% Compatible Python Standard `sqlite3` Vector Database Engine.
Provides direct connectivity with `import sqlite3; conn = sqlite3.connect(...)`
with custom Vector UDFs (KNN, COSINE_SIM, EMBED) and bidirectional synchronization
with binary VectorStorage (.vdb) and HNSWIndex.
"""

import json
import os
import sqlite3
from typing import Any, Dict, List, Optional, Tuple

from ..index.embedding import DeterministicEmbedding
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


def _open_raw_sqlite_connection(
    db_path: str, read_only: bool, timeout: float
) -> sqlite3.Connection:
    abs_path = os.path.abspath(db_path)
    if read_only:
        return sqlite3.connect(f"file:{abs_path}?mode=ro", uri=True, timeout=timeout)
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    return sqlite3.connect(abs_path, timeout=timeout)


def _init_papers_schema(
    conn: sqlite3.Connection, storage: Optional[VectorStorage]
) -> None:
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS papers (
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
        sync_from_vector_storage(conn, storage)


def get_sqlite_connection(
    db_path: str = "outputs/database/papers.db",
    storage: Optional[VectorStorage] = None,
    init_schema: bool = True,
    read_only: bool = False,
    enable_wal: bool = False,
    timeout: float = 5.0,
) -> sqlite3.Connection:
    """
    Returns standard `sqlite3.Connection` with full SQLite SQL support and vector UDFs.
    Usage:
        from database import get_sqlite_connection

        conn = get_sqlite_connection(
            "outputs/database/analytics/analytics.db",
            init_schema=False,
            enable_wal=True,
        )
        cursor = conn.cursor()
    """
    conn = _open_raw_sqlite_connection(db_path, read_only, timeout)
    conn.row_factory = sqlite3.Row
    register_vector_functions(conn)

    if enable_wal and not read_only:
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")

    if init_schema and not read_only:
        _init_papers_schema(conn, storage)

    return conn


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


def sync_from_vector_storage(
    conn: sqlite3.Connection, storage: VectorStorage, table_name: str = "papers"
) -> int:
    """Synchronizes records from binary VectorStorage into SQLite table."""
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
    conn: sqlite3.Connection, storage: VectorStorage, table_name: str = "papers"
) -> int:
    """Synchronizes records from SQLite table back into binary VectorStorage (.vdb)."""
    cur = conn.cursor()
    cur.execute(f"SELECT id, vector, metadata FROM {table_name} ORDER BY id ASC")
    rows = cur.fetchall()

    vectors: List[Tuple[float, ...]] = []
    metadata: List[Dict[str, Any]] = []

    for r in rows:
        vec_list = json.loads(r["vector"]) if r["vector"] else [0.0] * storage.dim
        meta_dict = json.loads(r["metadata"]) if r["metadata"] else {"id": r["id"]}
        vectors.append(tuple(vec_list))
        metadata.append(meta_dict)

    storage.write_all(vectors, metadata)
    return len(vectors)
