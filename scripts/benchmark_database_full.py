#!/usr/bin/env python3
"""
Comprehensive profiling workload benchmark for src/database.
Exercises SQL parsing/execution, storage engines, indexing, transactions, and PAX/vectorized engine.
"""

import os
import random
import sys
import tempfile
from typing import List

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC_DIR = os.path.join(REPO_ROOT, "src")
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)


def _gen_vector(dim: int = 64) -> List[float]:
    v = [random.uniform(-1.0, 1.0) for _ in range(dim)]
    norm = sum(x * x for x in v) ** 0.5
    return [x / (norm or 1.0) for x in v]


def bench_sql_relational_workload() -> None:
    """Exercises SQL DDL, DML (Insert, Update, Delete, Upsert), and DQL (Joins, CTE, Aggregations, Window functions)."""
    from database import connect

    conn = connect(":memory:")
    cursor = conn.cursor()

    # DDL
    cursor.execute("""
        CREATE TABLE departments (
            dept_id INTEGER PRIMARY KEY,
            dept_name TEXT NOT NULL,
            budget REAL
        )
        """)
    cursor.execute("""
        CREATE TABLE employees (
            emp_id INTEGER PRIMARY KEY,
            dept_id INTEGER,
            name TEXT NOT NULL,
            salary REAL,
            role TEXT,
            status TEXT DEFAULT 'active'
        )
        """)

    # DML: Inserts
    depts = [
        (1, "Security", 500000.0),
        (2, "AI Research", 800000.0),
        (3, "Platform", 400000.0),
    ]
    for d in depts:
        cursor.execute(
            "INSERT INTO departments (dept_id, dept_name, budget) VALUES (?, ?, ?)",
            d,
        )

    roles = ["Lead", "Senior", "Engineer", "Researcher", "Architect"]
    for i in range(1, 51):
        dept_id = (i % 3) + 1
        name = f"Emp_{i}"
        salary = 70000.0 + (i * 500.0)
        role = roles[i % len(roles)]
        cursor.execute(
            "INSERT INTO employees (emp_id, dept_id, name, salary, role) VALUES (?, ?, ?, ?, ?)",
            (i, dept_id, name, salary, role),
        )

    # DQL: Queries
    # 1. Joins + Aggregation + Group By + Having
    for _ in range(5):
        cursor.execute("""
            SELECT d.dept_name, COUNT(e.emp_id) AS emp_count, AVG(e.salary) AS avg_sal, MAX(e.salary) AS max_sal
            FROM departments AS d
            JOIN employees AS e ON d.dept_id = e.dept_id
            WHERE e.status = 'active' AND e.salary >= 75000.0
            GROUP BY d.dept_name
            HAVING emp_count > 3
            ORDER BY avg_sal DESC
            """)
        rows = cursor.fetchall()
        assert len(rows) > 0

    # 2. CTE + Subquery
    for _ in range(5):
        cursor.execute("""
            WITH high_earners AS (
                SELECT emp_id, name, dept_id, salary
                FROM employees
                WHERE salary > (SELECT AVG(salary) FROM employees)
            )
            SELECT he.name, d.dept_name, he.salary
            FROM high_earners he
            JOIN departments d ON he.dept_id = d.dept_id
            ORDER BY he.salary DESC
            LIMIT 10
            """)
        rows = cursor.fetchall()
        assert len(rows) <= 10

    # 3. Window functions & arithmetic
    for _ in range(5):
        cursor.execute("""
            SELECT emp_id, name, salary,
                   ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) as dept_rank
            FROM employees
            WHERE salary > 80000.0
            """)
        rows = cursor.fetchall()
        assert len(rows) > 0

    # 4. Updates & Deletes
    cursor.execute("UPDATE employees SET salary = salary * 1.05 WHERE dept_id = 1")
    cursor.execute("DELETE FROM employees WHERE emp_id > 45 RETURNING emp_id, name")
    deleted = cursor.fetchall()
    assert len(deleted) == 5

    conn.close()


def bench_vector_and_hnsw_workload() -> None:
    """Exercises VectorStorage and HNSW approximate nearest neighbor search."""
    from database import HNSWIndex, RoaringBitmapIndex, VectorStorage

    dim = 16
    num_vectors = 60

    # 1. HNSW Index build and query
    index = HNSWIndex(dim=dim, M=8, ef_construction=16, ef_search=12)
    vectors = [_gen_vector(dim) for _ in range(num_vectors)]
    for i, vec in enumerate(vectors):
        index.insert(i, vec)

    for _ in range(10):
        q = _gen_vector(dim)
        res = index.search(q, top_k=5)
        assert len(res) == 5

    # 2. VectorStorage batch append and lookup
    with tempfile.TemporaryDirectory() as tmpdir:
        vdb_path = os.path.join(tmpdir, "test.vdb")
        storage = VectorStorage(vdb_path, dim=dim)
        metas = [{"doc_id": f"doc_{i}", "category": "sec"} for i in range(num_vectors)]
        storage.append_batch(vectors, metas)
        for i in range(0, num_vectors, 10):
            v = storage.get_vector(i)
            m = storage.get_metadata(i)
            assert len(v) == dim
            assert m["category"] == "sec"
        storage.close()

    # 3. Roaring Bitmap index operations
    b1 = RoaringBitmapIndex("severity", cardinality_threshold=100)
    for x in range(0, 300):
        b1.insert(f"tag_{x % 10}", x)
    res_in = b1.lookup_in(["tag_0", "tag_1"])
    assert len(res_in) > 0
    assert b1.cardinality() == 10


def bench_storage_primitives_workload() -> None:
    """Exercises BPlusTree, LSMTreeEngine, SlottedPage, and Pager WAL."""
    from database import BPlusTree, LSMTreeEngine, Pager

    # 1. B+Tree insertions and range queries
    btree = BPlusTree(column_name="id")
    keys = list(range(100))
    random.shuffle(keys)
    for k in keys:
        btree.insert(k, k)
    for k in range(0, 100, 10):
        val = btree.search(k)
        assert k in val
    range_res = btree.range_scan(20, 50)
    assert len(range_res) == 31

    # 2. LSM-Tree Engine put, flush, get
    with tempfile.TemporaryDirectory() as tmpdir:
        lsm = LSMTreeEngine(data_dir=tmpdir, max_memtable_bytes=4096)
        for i in range(80):
            lsm.put(f"lsm_key_{i:04d}", f"lsm_val_{i}")
        for i in range(0, 80, 10):
            val = lsm.get(f"lsm_key_{i:04d}")
            assert val == f"lsm_val_{i}"
        lsm.close()

    # 3. Pager & 2Q PageCache
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "pager.db")
        pager = Pager(db_path, cache_capacity=16)
        pager.begin()
        for p in range(10):
            pager.write_page(p, bytes([p % 256] * 4096))
        pager.commit()
        for p in range(10):
            data = pager.read_page(p)
            assert len(data) == 4096
        pager.close()


def bench_pax_and_vectorized_workload() -> None:
    """Exercises PAX columnar storage and vectorized scans/aggregations."""
    from database import VectorizedAggregation, VectorizedFilter, VectorizedScan

    # 1. Vectorized scan, filter, aggregate
    num_rows = 500
    rows = [
        {"id": i, "score": float(i * 1.5), "cat": ["A", "B", "C"][i % 3]}
        for i in range(num_rows)
    ]

    vscan = VectorizedScan(rows, batch_size=64)
    vfilter = VectorizedFilter(
        vscan, lambda b: [x >= 50.0 for x in b.get_column("score")]
    )
    avg_score = VectorizedAggregation.aggregate(vfilter, "score", "AVG")
    assert avg_score is not None and avg_score > 0


def bench_transactions_and_lock_workload() -> None:
    """Exercises MVCC and LockManager."""
    from database import LockManager, LockMode, MVCCManager

    # 1. MVCC transactions
    mvcc = MVCCManager()
    t1 = mvcc.begin_transaction()
    t2 = mvcc.begin_transaction()

    mvcc.insert(t1, "row_1", {"col": "v1"})
    mvcc.commit_transaction(t1)

    t3 = mvcc.begin_transaction()
    val3 = mvcc.get(t3, "row_1")
    assert val3 is not None
    mvcc.commit_transaction(t3)
    mvcc.commit_transaction(t2)

    # 2. LockManager
    lm = LockManager()
    lm.acquire_lock(101, "res_A", LockMode.EXCLUSIVE)
    lm.acquire_lock(101, "res_B", LockMode.SHARED)
    assert lm.is_locked("res_A")
    assert lm.is_locked("res_B")
    lm.release_all_locks(101)
    assert not lm.is_locked("res_A")


def main() -> None:
    print("[*] Starting comprehensive database benchmark...")
    bench_sql_relational_workload()
    bench_vector_and_hnsw_workload()
    bench_storage_primitives_workload()
    bench_pax_and_vectorized_workload()
    bench_transactions_and_lock_workload()
    print("[*] Database benchmark completed successfully.")


if __name__ == "__main__":
    main()
