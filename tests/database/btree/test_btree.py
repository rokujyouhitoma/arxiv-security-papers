#!/usr/bin/env python3
"""
Unit tests for B+Tree 4KB Paged Index and Cost-Based Query Planner (Issue 033).
"""

import os
import sys
import tempfile

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from database.btree import BPlusTree, BTreeNode
from database.pager import Pager
from database.planner import ColumnStats, CostModel, PlanType, QueryPlanner, TableStats
from database.sql import SelectStatement, SQLExecutor, SQLParser, TableCatalog
from database.storage import VectorStorage


def test_btree_node_serialization_and_split():
    node = BTreeNode(page_id=1, is_leaf=True)
    for i in range(10):
        node.insert_leaf_entry(f"key_{i:03d}", i * 10)

    raw_bytes = node.serialize()
    assert len(raw_bytes) == 4096

    deserialized = BTreeNode.deserialize(1, raw_bytes)
    assert deserialized.page_id == 1
    assert deserialized.is_leaf is True
    assert len(deserialized.keys) == 10
    assert deserialized.keys[0] == "key_000"

    # Test split
    promoted_key, sibling = node.split(new_page_id=2)
    assert sibling.page_id == 2
    assert len(node.keys) == 5
    assert len(sibling.keys) == 5
    assert node.next_leaf == 2


def test_bplus_tree_operations_in_memory():
    tree = BPlusTree(column_name="score")

    # Insert 200 items with duplicate and unique keys
    entries = [(i % 50, i) for i in range(200)]
    for k, row_id in entries:
        tree.insert(k, row_id)

    # Point search
    results_25 = tree.search(25)
    assert len(results_25) == 4
    assert 25 in results_25
    assert 75 in results_25

    # Missing search
    assert tree.search(999) == []

    # Range scan [10, 20]
    range_res = tree.range_scan(
        min_key=10, max_key=20, include_min=True, include_max=True
    )
    expected_rows = [row_id for k, row_id in entries if 10 <= k <= 20]
    assert sorted(range_res) == sorted(expected_rows)

    # Open-ended range scan
    gt_45 = tree.range_scan(min_key=45, include_min=False)
    expected_gt_45 = [row_id for k, row_id in entries if k > 45]
    assert sorted(gt_45) == sorted(expected_gt_45)

    # Delete
    deleted = tree.delete(25, 25)
    assert deleted is True
    after_del = tree.search(25)
    assert 25 not in after_del
    assert len(after_del) == 3


def test_bplus_tree_with_4kb_pager():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_btree.db")
        pager = Pager(db_path, vfs_name="posix")

        tree = BPlusTree(pager=pager, column_name="year")

        # Insert 300 years
        for i in range(300):
            tree.insert(2000 + (i % 25), i)

        pager.commit()

        # Search
        res_2020 = tree.search(2020)
        assert len(res_2020) == 12

        # Range scan 2020 to 2024
        range_res = tree.range_scan(min_key=2020, max_key=2024)
        assert len(range_res) == 12 * 5
        pager.close()


def test_planner_stats_and_cost_model():
    table_stats = TableStats("papers", total_rows=1000)
    metadata = [
        {
            "id": i,
            "category": "crypto" if i % 10 == 0 else "network",
            "year": 2000 + (i % 20),
        }
        for i in range(1000)
    ]
    table_stats.analyze_from_metadata(metadata)

    assert table_stats.total_rows == 1000
    assert "category" in table_stats.columns
    assert table_stats.columns["category"].distinct_count == 2
    assert table_stats.columns["year"].min_value == 2000
    assert table_stats.columns["year"].max_value == 2019

    # Selectivity
    cat_sel = table_stats.columns["category"].estimate_selectivity("=", "crypto")
    assert round(cat_sel, 2) == 0.1

    # Cost model
    t_scan_cost = CostModel.estimate_table_scan_cost(1000)
    assert t_scan_cost > 0

    idx_scan_cost = CostModel.estimate_index_scan_cost(1000, selectivity=0.01)
    assert idx_scan_cost < t_scan_cost

    # Hybrid cost
    plan_type, hybrid_cost = CostModel.estimate_hybrid_cost(
        total_rows=1000, selectivity=0.02, top_k=10, has_index=True
    )
    assert plan_type == PlanType.HYBRID_FILTER_FIRST


def test_query_planner_and_explain_sql():
    parser = SQLParser()
    sql_select = "SELECT * FROM papers WHERE year = 2024"
    stmt = parser.parse(sql_select)
    assert isinstance(stmt, SelectStatement)

    table_stats = TableStats("papers", total_rows=5000)
    col_stat = ColumnStats("year")
    col_stat.total_count = 5000
    col_stat.distinct_count = 50
    table_stats.columns["year"] = col_stat

    # With Index available
    plan = QueryPlanner.plan_select(
        stmt, table_stats, available_indexes={"year": "idx_papers_year"}
    )
    assert plan.plan_type == PlanType.INDEX_SCAN
    assert plan.selected_index == "idx_papers_year"

    # Explain output
    explain_rows = QueryPlanner.explain(
        stmt, table_stats, available_indexes={"year": "idx_papers_year"}
    )
    assert len(explain_rows) == 1
    assert "USING INDEX idx_papers_year" in explain_rows[0]["detail"]


def test_sql_executor_btree_and_explain_integration():
    with tempfile.TemporaryDirectory() as tmpdir:
        storage_path = os.path.join(tmpdir, "papers.vdb")
        storage = VectorStorage(storage_path, dim=8)
        vecs = [[0.1 * ((i + j) % 10) for j in range(8)] for i in range(500)]
        meta = [
            {"id": i, "year": 2000 + (i % 25), "title": f"Paper {i}"}
            for i in range(500)
        ]
        storage.write_all(vecs, meta)

        executor = SQLExecutor()
        cat = TableCatalog(name="papers", storage=storage)
        executor.tables["papers"] = cat

        # 1. Create BTree Index on year
        res_idx = executor.execute(
            "CREATE INDEX idx_papers_year ON papers(year) USING BTREE"
        )
        assert res_idx["status"] == "ok"
        assert "year" in cat.btree_indexes
        assert len(cat.btree_indexes["year"].search(2005)) == 20

        # 2. EXPLAIN QUERY PLAN
        res_explain = executor.execute(
            "EXPLAIN QUERY PLAN SELECT * FROM papers WHERE year = 2005"
        )
        assert res_explain["status"] == "ok"
        assert len(res_explain["rows"]) == 1
        assert "idx_papers_year" in res_explain["rows"][0]["detail"]

        # 3. Standard Select still functional
        res_sel = executor.execute(
            "SELECT id, year, title FROM papers WHERE year = 2005"
        )
        assert res_sel["status"] == "ok"
        assert len(res_sel["rows"]) == 20
