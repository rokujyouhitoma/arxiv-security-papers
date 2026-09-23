#!/usr/bin/env python3
"""
Benchmark for Transaction Operations (Issue 383):
1. BEGIN TRANSACTION latency with varying table sizes (1k, 5k, 10k rows)
2. ROLLBACK latency after small mutation on large table (100 inserts on 10k table)
3. SAVEPOINT / ROLLBACK TO SAVEPOINT latency

Used for Issue 383 baseline & post-optimization verification.
"""

import time
from typing import Any, Dict


def run_benchmark() -> Dict[str, Any]:
    import os
    import sys

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_dir = os.path.join(repo_root, "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from database import connect

    conn = connect(":memory:")
    cursor = conn.cursor()

    # Create tables
    cursor.execute("""
        CREATE TABLE large_table (
            id INTEGER PRIMARY KEY,
            val TEXT,
            num REAL
        )
    """)
    cursor.execute("""
        CREATE TABLE secondary_table (
            id INTEGER PRIMARY KEY,
            name TEXT
        )
    """)

    # Populate 10,000 rows
    num_rows = 10000
    batch_data = [(i, f"data_val_{i}", float(i * 1.5)) for i in range(1, num_rows + 1)]
    cursor.executemany("INSERT INTO large_table (id, val, num) VALUES (?, ?, ?)", batch_data)
    sec_data = [(i, f"sec_{i}") for i in range(1, 1001)]
    cursor.executemany("INSERT INTO secondary_table (id, name) VALUES (?, ?)", sec_data)

    # 1. Measure BEGIN TRANSACTION latency (averaged over 20 runs)
    # Notice: In sqlite / custom db, BEGIN starts a tx
    begin_times = []
    for _ in range(20):
        t0 = time.perf_counter()
        cursor.execute("BEGIN TRANSACTION")
        t_begin = time.perf_counter() - t0
        begin_times.append(t_begin)
        cursor.execute("COMMIT")

    avg_begin_sec = sum(begin_times) / len(begin_times)

    # 2. Measure ROLLBACK after inserting 100 rows into 10,000 row table
    rollback_times = []
    for i in range(5):
        cursor.execute("BEGIN TRANSACTION")
        ins_data = [(num_rows + 100 * (i + 1) + j, f"temp_{j}", 99.9) for j in range(100)]
        cursor.executemany("INSERT INTO large_table (id, val, num) VALUES (?, ?, ?)", ins_data)
        t0 = time.perf_counter()
        cursor.execute("ROLLBACK")
        t_rollback = time.perf_counter() - t0
        rollback_times.append(t_rollback)

    avg_rollback_sec = sum(rollback_times) / len(rollback_times)

    # 3. Measure SAVEPOINT and ROLLBACK TO SAVEPOINT
    cursor.execute("BEGIN TRANSACTION")
    sp_times = []
    rb_sp_times = []
    for i in range(5):
        t0 = time.perf_counter()
        cursor.execute(f"SAVEPOINT sp_{i}")
        sp_times.append(time.perf_counter() - t0)

        # mutate
        cursor.execute(f"INSERT INTO secondary_table (id, name) VALUES ({2000 + i}, 'sp_item')")

        t0 = time.perf_counter()
        cursor.execute(f"ROLLBACK TO SAVEPOINT sp_{i}")
        rb_sp_times.append(time.perf_counter() - t0)

    cursor.execute("COMMIT")
    avg_savepoint_sec = sum(sp_times) / len(sp_times)
    avg_rb_savepoint_sec = sum(rb_sp_times) / len(rb_sp_times)

    conn.close()

    return {
        "begin_sec": avg_begin_sec,
        "begin_ops_sec": 1.0 / avg_begin_sec if avg_begin_sec > 0 else 0.0,
        "rollback_100_rows_sec": avg_rollback_sec,
        "rollback_ops_sec": 1.0 / avg_rollback_sec if avg_rollback_sec > 0 else 0.0,
        "savepoint_sec": avg_savepoint_sec,
        "savepoint_ops_sec": 1.0 / avg_savepoint_sec if avg_savepoint_sec > 0 else 0.0,
        "rollback_to_savepoint_sec": avg_rb_savepoint_sec,
        "rollback_to_savepoint_ops_sec": (
            1.0 / avg_rb_savepoint_sec if avg_rb_savepoint_sec > 0 else 0.0
        ),
    }


def main() -> None:
    print("=== Issue 383: Transaction Snapshot & Rollback Latency Benchmark ===")
    res = run_benchmark()
    b_ms, b_ops = res["begin_sec"] * 1000.0, res["begin_ops_sec"]
    rb_ms, rb_ops = res["rollback_100_rows_sec"] * 1000.0, res["rollback_ops_sec"]
    sp_ms, sp_ops = res["savepoint_sec"] * 1000.0, res["savepoint_ops_sec"]
    rb_sp_ms = res["rollback_to_savepoint_sec"] * 1000.0
    rb_sp_ops = res["rollback_to_savepoint_ops_sec"]

    print(f"  BEGIN (10k rows table):           {b_ms:.3f} ms ({b_ops:.1f} ops/s)")
    print(f"  ROLLBACK (100 dirty on 10k):      {rb_ms:.3f} ms ({rb_ops:.1f} ops/s)")
    print(f"  SAVEPOINT (10k rows table):       {sp_ms:.3f} ms ({sp_ops:.1f} ops/s)")
    print(f"  ROLLBACK TO SP (1 item dirty):    {rb_sp_ms:.3f} ms ({rb_sp_ops:.1f} ops/s)")


if __name__ == "__main__":
    main()
