#!/usr/bin/env python3
"""
Benchmark for pure relational CRUD (Insert, Select, Delete) performance.
Used to measure baseline and post-optimization performance for Issue 380:
Decouple HNSW from relational tables and prevent write amplification.
"""

import time
from typing import Dict


def bench_relational_insert_and_delete(num_rows: int = 500) -> Dict[str, float]:
    import os
    import sys

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_dir = os.path.join(repo_root, "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from database import connect

    conn = connect(":memory:")
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE users (
            user_id INTEGER PRIMARY KEY,
            username TEXT NOT NULL,
            email TEXT,
            score REAL,
            status TEXT DEFAULT 'active'
        )
    """)

    # 1. Measure pure INSERT latency & throughput
    t_insert_0 = time.perf_counter()
    for i in range(1, num_rows + 1):
        cursor.execute(
            "INSERT INTO users (user_id, username, email, score) VALUES (?, ?, ?, ?)",
            (i, f"user_{i}", f"user_{i}@example.com", float(i * 10.0)),
        )
    insert_duration = time.perf_counter() - t_insert_0

    # 2. Measure SELECT latency
    t_select_0 = time.perf_counter()
    cursor.execute("SELECT * FROM users WHERE score >= 2500.0")
    rows = cursor.fetchall()
    select_duration = time.perf_counter() - t_select_0
    assert len(rows) > 0

    # 3. Measure DELETE latency (rebuilding vs non-rebuilding)
    # Delete half the rows
    t_delete_0 = time.perf_counter()
    cursor.execute("DELETE FROM users WHERE user_id > 250")
    delete_duration = time.perf_counter() - t_delete_0

    conn.close()

    insert_qps = num_rows / insert_duration if insert_duration > 0 else 0.0

    return {
        "num_rows": float(num_rows),
        "insert_duration_sec": insert_duration,
        "insert_qps": insert_qps,
        "avg_insert_latency_ms": (insert_duration / num_rows) * 1000.0,
        "select_duration_sec": select_duration,
        "delete_duration_sec": delete_duration,
    }


def main() -> None:
    print("=== Issue 380: Relational CRUD Performance Benchmark ===")
    res = bench_relational_insert_and_delete(num_rows=500)
    print(f"  Rows inserted:        {int(res['num_rows'])}")
    print(f"  Insert Total Time:    {res['insert_duration_sec']:.4f} s")
    print(f"  Insert Throughput:    {res['insert_qps']:.2f} rows/s")
    print(f"  Avg Insert Latency:   {res['avg_insert_latency_ms']:.4f} ms/row")
    print(f"  Select Time:          {res['select_duration_sec']:.4f} s")
    print(f"  Delete Time:          {res['delete_duration_sec']:.4f} s")


if __name__ == "__main__":
    main()
