#!/usr/bin/env python3
"""
Python Standard Library `sqlite3` Interoperability Bridge.
Enables standard `sqlite3.connect()` clients to query vector data and execute
`KNN()` and `COSINE_SIM()` functions directly inside standard SQLite queries.
"""

import json
import sqlite3
from typing import Any, List, Optional

from ..storage.storage import VectorStorage


def _parse_vector_arg(v_raw: Any) -> List[float]:
    """Parses JSON string or sequence into float list."""
    if isinstance(v_raw, str):
        return json.loads(v_raw)
    return list(v_raw)


def cosine_similarity(v1_raw: Any, v2_raw: Any) -> float:
    """SQLite User-Defined Function (UDF) computing cosine similarity."""
    try:
        v1 = _parse_vector_arg(v1_raw)
        v2 = _parse_vector_arg(v2_raw)
        if len(v1) != len(v2) or not v1:
            return 0.0
        dot = sum(a * b for a, b in zip(v1, v2))
        return float(max(0.0, min(1.0, dot)))
    except Exception:
        return 0.0


def _build_sqlite_record(
    idx: int, storage: VectorStorage
) -> tuple[str, str, str, str, str, str]:
    """Constructs a single row tuple for SQLite insertion."""
    meta = storage.get_metadata(idx)
    vec = list(storage.get_vector(idx))
    doc_id = str(meta.get("id", str(idx)))
    title = str(meta.get("title", ""))
    desc = str(meta.get("description", ""))
    cat = str(meta.get("category", ""))
    return (
        doc_id,
        title,
        desc,
        cat,
        json.dumps(vec),
        json.dumps(meta, ensure_ascii=False),
    )


def attach_to_sqlite(
    sqlite_conn: sqlite3.Connection,
    storage: Optional[VectorStorage] = None,
    table_name: str = "papers",
) -> None:
    """
    Attaches custom Vector functions (COSINE_SIM, KNN) and populates SQLite
    table with vector metadata from VectorStorage.
    """
    sqlite_conn.create_function("COSINE_SIM", 2, cosine_similarity)
    sqlite_conn.create_function("KNN_SCORE", 2, cosine_similarity)

    if not storage:
        return

    cur = sqlite_conn.cursor()
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            id TEXT PRIMARY KEY,
            title TEXT,
            description TEXT,
            category TEXT,
            vector TEXT,
            metadata TEXT
        )
        """)

    records = [_build_sqlite_record(idx, storage) for idx in range(storage.count)]
    if records:
        cur.executemany(
            f"""
            INSERT OR REPLACE INTO {table_name} (id, title, description, category, vector, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            records,
        )
    sqlite_conn.commit()
