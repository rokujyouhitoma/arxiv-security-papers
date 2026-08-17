#!/usr/bin/env python3
"""
Python Standard Library `sqlite3` Interoperability Bridge.
Enables standard `sqlite3.connect()` clients to query vector data and execute
`KNN()` and `COSINE_SIM()` functions directly inside standard SQLite queries.
"""

import json
import sqlite3
from typing import Any, List, Optional, Sequence

from .embedding import DeterministicEmbedding
from .storage import VectorStorage


def cosine_similarity(v1_raw: Any, v2_raw: Any) -> float:
    """SQLite User-Defined Function (UDF) computing cosine similarity."""
    try:
        v1: List[float] = (
            json.loads(v1_raw) if isinstance(v1_raw, str) else list(v1_raw)
        )
        v2: List[float] = (
            json.loads(v2_raw) if isinstance(v2_raw, str) else list(v2_raw)
        )
        if len(v1) != len(v2) or not v1:
            return 0.0
        # Dot product of unit vectors
        dot = sum(a * b for a, b in zip(v1, v2))
        return float(max(0.0, min(1.0, dot)))
    except Exception:
        return 0.0


def attach_to_sqlite(
    sqlite_conn: sqlite3.Connection,
    storage: Optional[VectorStorage] = None,
    table_name: str = "papers",
) -> None:
    """
    Attaches custom Vector functions (COSINE_SIM, KNN) and populates SQLite
    table with vector metadata from VectorStorage.
    """
    # 1. Register UDFs in SQLite
    sqlite_conn.create_function("COSINE_SIM", 2, cosine_similarity)
    sqlite_conn.create_function("KNN_SCORE", 2, cosine_similarity)

    embedder = DeterministicEmbedding()

    # 2. If storage is provided, mirror records into SQLite table
    if storage:
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

        if records:
            cur.executemany(
                f"""
                INSERT OR REPLACE INTO {table_name} (id, title, description, category, vector, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                records,
            )
        sqlite_conn.commit()
