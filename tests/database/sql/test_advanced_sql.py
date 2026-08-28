#!/usr/bin/env python3
"""
Unit tests for Advanced SQL capabilities in src/database/sql:
- Multi-table INNER/LEFT JOINs
- Recursive CTEs (WITH RECURSIVE) for graph / hierarchy traversal
- JSON operators (->, ->>)
- Table aliases and column projections
"""

import json
from typing import Any

import pytest

from database.embedding import DeterministicEmbedding
from database.sql import SQLExecutor


@pytest.fixture
def advanced_sql_executor(tmp_path: Any) -> SQLExecutor:
    embedding = DeterministicEmbedding(dim=16)
    executor = SQLExecutor(embedding=embedding)

    # 1. Create vertices table
    executor.execute(
        "CREATE TABLE vertices (id TEXT PRIMARY KEY, label TEXT, properties JSON)"
    )
    # 2. Create edges table
    executor.execute(
        "CREATE TABLE edges (src_id TEXT, dst_id TEXT, label TEXT, properties JSON)"
    )

    # Insert Vertices
    v_data = [
        ("paper_1", "Paper", json.dumps({"title": "Zero Trust in Mesh", "year": 2026})),
        (
            "cve_1",
            "Vulnerability",
            json.dumps({"cve_id": "CVE-2026-9999", "cvss": 9.8}),
        ),
        (
            "mitre_1",
            "AttackTechnique",
            json.dumps({"technique_id": "T1059", "name": "Command Injection"}),
        ),
        (
            "defense_1",
            "Defense",
            json.dumps({"name": "Zero Trust Auth", "framework": "NIST SP 800-207"}),
        ),
        ("unlinked_node", "Isolated", json.dumps({"note": "No edges"})),
    ]
    for vid, lbl, props in v_data:
        executor.execute(
            f"INSERT INTO vertices (id, label, properties) VALUES ('{vid}', '{lbl}', '{props}')"
        )

    # Insert Edges
    e_data = [
        ("paper_1", "cve_1", "ANALYZES", json.dumps({"confidence": 0.95})),
        ("cve_1", "mitre_1", "EXPLOITED_BY", json.dumps({"impact": "HIGH"})),
        ("defense_1", "mitre_1", "MITIGATES", json.dumps({"effectiveness": "HIGH"})),
    ]
    for src, dst, lbl, props in e_data:
        executor.execute(
            f"INSERT INTO edges (src_id, dst_id, label, properties) VALUES ('{src}', '{dst}', '{lbl}', '{props}')"
        )

    return executor


def test_json_operators_and_aliases(advanced_sql_executor: SQLExecutor) -> None:
    # Test JSON unquoted extraction (->>) and column alias
    sql = (
        "SELECT id, properties->>'title' AS paper_title, properties->>'year' AS pub_year "
        "FROM vertices WHERE label = 'Paper'"
    )
    res = advanced_sql_executor.execute(sql)

    assert res["status"] == "ok"
    assert res["count"] == 1
    row = res["rows"][0]
    assert row["id"] == "paper_1"
    assert row["paper_title"] == "Zero Trust in Mesh"
    assert row["pub_year"] == "2026"


def test_multi_table_inner_join(advanced_sql_executor: SQLExecutor) -> None:
    # 2-Table JOIN: Paper -> Edge
    sql = """
    SELECT p.id AS paper_id, e.dst_id AS target_cve, e.label AS edge_type
    FROM vertices p
    JOIN edges e ON e.src_id = p.id
    WHERE p.id = 'paper_1'
    """
    res = advanced_sql_executor.execute(sql)
    assert res["status"] == "ok"
    assert res["count"] == 1
    row = res["rows"][0]
    assert row["paper_id"] == "paper_1"
    assert row["target_cve"] == "cve_1"
    assert row["edge_type"] == "ANALYZES"


def test_three_hop_causal_graph_join(advanced_sql_executor: SQLExecutor) -> None:
    # 3-Hop Multi-JOIN: Paper -> Vulnerability -> AttackTechnique <- Defense
    sql = """
    SELECT p.id AS paper_id,
           v.properties->>'cve_id' AS cve,
           t.properties->>'name' AS attack_name,
           d.properties->>'name' AS defense_name
    FROM vertices p
    JOIN edges e1 ON e1.src_id = p.id AND e1.label = 'ANALYZES'
    JOIN vertices v ON v.id = e1.dst_id
    JOIN edges e2 ON e2.src_id = v.id AND e2.label = 'EXPLOITED_BY'
    JOIN vertices t ON t.id = e2.dst_id
    JOIN edges e3 ON e3.dst_id = t.id AND e3.label = 'MITIGATES'
    JOIN vertices d ON d.id = e3.src_id
    WHERE p.id = 'paper_1'
    """
    res = advanced_sql_executor.execute(sql)
    assert res["status"] == "ok"
    assert res["count"] == 1
    row = res["rows"][0]
    assert row["paper_id"] == "paper_1"
    assert row["cve"] == "CVE-2026-9999"
    assert row["attack_name"] == "Command Injection"
    assert row["defense_name"] == "Zero Trust Auth"


def test_left_outer_join(advanced_sql_executor: SQLExecutor) -> None:
    # Left JOIN returns unlinked nodes with None edges
    sql = """
    SELECT v.id AS node_id, e.label AS edge_label
    FROM vertices v
    LEFT JOIN edges e ON e.src_id = v.id
    WHERE v.id = 'unlinked_node'
    """
    res = advanced_sql_executor.execute(sql)
    assert res["status"] == "ok"
    assert res["count"] == 1
    row = res["rows"][0]
    assert row["node_id"] == "unlinked_node"
    assert row["edge_label"] is None


def test_recursive_cte_graph_traversal(advanced_sql_executor: SQLExecutor) -> None:
    # Recursive CTE traversing from paper_1 forward along edges
    sql = """
    WITH RECURSIVE graph_path AS (
        SELECT id, 0 AS depth
        FROM vertices
        WHERE id = 'paper_1'
        UNION ALL
        SELECT e.dst_id AS id, gp.depth + 1 AS depth
        FROM graph_path gp
        JOIN edges e ON gp.id = e.src_id
        WHERE gp.depth < 3
    )
    SELECT id, depth FROM graph_path ORDER BY depth ASC
    """
    res = advanced_sql_executor.execute(sql)
    assert res["status"] == "ok"
    # Should find paper_1 (depth 0), cve_1 (depth 1), mitre_1 (depth 2)
    assert res["count"] == 3
    rows = res["rows"]
    assert rows[0]["id"] == "paper_1"
    assert rows[0]["depth"] == 0
    assert rows[1]["id"] == "cve_1"
    assert rows[1]["depth"] == 1
    assert rows[2]["id"] == "mitre_1"
    assert rows[2]["depth"] == 2


def test_show_databases_and_tables(advanced_sql_executor: SQLExecutor) -> None:
    # 1. SHOW DATABASES
    res_db = advanced_sql_executor.execute("SHOW DATABASES")
    assert res_db["status"] == "ok"
    assert res_db["target"] == "DATABASES"
    db_names = [r["Database"] for r in res_db["rows"]]
    assert "arxiv_security_db" in db_names

    # 2. SHOW TABLES
    res_tbl = advanced_sql_executor.execute("SHOW TABLES")
    assert res_tbl["status"] == "ok"
    assert res_tbl["target"] == "TABLES"
    assert res_tbl["count"] >= 2
    tbl_names = [r["Table"] for r in res_tbl["rows"]]
    assert "vertices" in tbl_names
    assert "edges" in tbl_names

    # 3. SHOW TABLE STATUS
    res_st = advanced_sql_executor.execute("SHOW TABLE STATUS")
    assert res_st["status"] == "ok"
    assert res_st["target"] == "TABLE_STATUS"
    assert len(res_st["rows"]) >= 2
