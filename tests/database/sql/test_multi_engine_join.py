#!/usr/bin/env python3
"""
Integration tests for Cross-Engine SQL JOIN (Issue #229 / DSN-05 Section 21.7).
Verifies that ExecutionEngine can transparently JOIN across binary_vdb, json_table, and file_plain_text tables.
Pure Python, zero external dependencies.
"""

import os
import tempfile

from database.sql.executor import SQLExecutor
from database.storage.storage import VectorStorage


def test_cross_engine_transparent_join() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        # 1. Setup JSON catalog table file
        json_path = os.path.join(tmpdir, "papers.json")
        with open(json_path, "w", encoding="utf-8") as f:
            f.write(
                '{"p1": {"id": "p1", "title": "Quantum Safe Crypto"}, '
                '"p2": {"id": "p2", "title": "BGP Hijacking Mitigation"}}'
            )

        # 2. Setup PlainText Markdown virtual table directory
        docs_dir = os.path.join(tmpdir, "docs")
        os.makedirs(docs_dir, exist_ok=True)
        with open(os.path.join(docs_dir, "p1.md"), "w", encoding="utf-8") as f:
            f.write(
                "---\ntitle: 'Quantum Safe'\n---\nPost-quantum signatures evaluation."
            )
        with open(os.path.join(docs_dir, "p2.md"), "w", encoding="utf-8") as f:
            f.write("---\ntitle: 'BGP Routing'\n---\nRPKI route origin authorizations.")

        # 3. Initialize SQLExecutor
        vdb_path = os.path.join(tmpdir, "main.vdb")
        storage = VectorStorage(vdb_path, dim=4)
        engine = SQLExecutor(default_storage=storage)

        # 4. Create Tables using different storage backends
        # Table A: json_table
        res_a = engine.execute(
            f"CREATE TABLE papers (id TEXT PRIMARY KEY, title TEXT) "
            f"USING json_table LOCATION '{json_path}'"
        )
        assert res_a["status"] == "ok"

        # Table B: file_plain_text (virtual mount)
        res_b = engine.execute(
            f"CREATE TABLE docs (id TEXT PRIMARY KEY, body_markdown TEXT) "
            f"USING file_plain_text LOCATION '{docs_dir}'"
        )
        assert res_b["status"] == "ok"

        # Table C: binary_vdb (internal slotted vector storage)
        res_c = engine.execute(
            "CREATE TABLE scores (id TEXT PRIMARY KEY, score REAL) USING binary_vdb"
        )
        assert res_c["status"] == "ok"

        # Insert records into binary_vdb scores table
        engine.execute("INSERT INTO scores (id, score) VALUES ('p1', 98.5)")
        engine.execute("INSERT INTO scores (id, score) VALUES ('p2', 82.0)")

        # 5. Execute Cross-Engine Multi-Table JOIN
        join_sql = (
            "SELECT papers.title, docs.body_markdown, scores.score "
            "FROM papers "
            "JOIN docs ON papers.id = docs.id "
            "JOIN scores ON papers.id = scores.id"
        )
        res_join = engine.execute(join_sql)

        assert res_join["command"] == "SELECT"
        rows = res_join["rows"]
        assert len(rows) == 2

        # Verify combined attributes across 3 disparate storage engines
        row_map = {r["title"]: r for r in rows}
        assert "Quantum Safe Crypto" in row_map
        p1_row = row_map["Quantum Safe Crypto"]
        assert "Post-quantum signatures" in p1_row["body_markdown"]
        assert p1_row["score"] == 98.5

        assert "BGP Hijacking Mitigation" in row_map
        p2_row = row_map["BGP Hijacking Mitigation"]
        assert "RPKI route origin" in p2_row["body_markdown"]
        assert p2_row["score"] == 82.0
