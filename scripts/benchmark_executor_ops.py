#!/usr/bin/env python3
"""
Benchmark for SQLExecutor operations:
1. Equi-Join (INNER JOIN / LEFT JOIN)
2. UNIQUE constraint validation during INSERT
3. Relational WHERE clause evaluation

Used for Issue 382 baseline & post-optimization verification.
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

    # 1. Table setup for Join
    cursor.execute("""
        CREATE TABLE customers (
            id INTEGER PRIMARY KEY,
            name TEXT,
            country TEXT
        )
    """)
    cursor.execute("""
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY,
            customer_id INTEGER,
            amount REAL
        )
    """)

    num_customers = 500
    num_orders = 1000

    cust_data = [(i, f"customer_{i}", "JP" if i % 2 == 0 else "US") for i in range(1, num_customers + 1)]
    cursor.executemany("INSERT INTO customers (id, name, country) VALUES (?, ?, ?)", cust_data)

    order_data = [(i, (i % num_customers) + 1, float(i * 10)) for i in range(1, num_orders + 1)]
    cursor.executemany("INSERT INTO orders (id, customer_id, amount) VALUES (?, ?, ?)", order_data)

    # Measure Join
    t0_inner_join = time.perf_counter()
    for _ in range(5):
        cursor.execute("""
            SELECT orders.id, customers.name, orders.amount
            FROM orders
            INNER JOIN customers ON orders.customer_id = customers.id
        """)
        rows = cursor.fetchall()
        assert len(rows) == num_orders
    inner_join_duration = (time.perf_counter() - t0_inner_join) / 5.0

    t0_left_join = time.perf_counter()
    for _ in range(5):
        cursor.execute("""
            SELECT orders.id, customers.name, orders.amount
            FROM orders
            LEFT JOIN customers ON orders.customer_id = customers.id
        """)
        rows = cursor.fetchall()
        assert len(rows) == num_orders
    left_join_duration = (time.perf_counter() - t0_left_join) / 5.0

    # 2. Measure Unique Constraint INSERT
    cursor.execute("""
        CREATE TABLE unique_items (
            id INTEGER PRIMARY KEY,
            code TEXT UNIQUE,
            val INTEGER
        )
    """)
    num_unique_rows = 1500
    unique_data = [(i, f"CODE_{i}", i * 10) for i in range(1, num_unique_rows + 1)]
    t0_unique_insert = time.perf_counter()
    for item in unique_data:
        cursor.execute("INSERT INTO unique_items (id, code, val) VALUES (?, ?, ?)", item)
    unique_insert_duration = time.perf_counter() - t0_unique_insert

    # 3. Measure Relational Filter (WHERE numeric comparison)
    t0_rel_filter = time.perf_counter()
    for _ in range(10):
        cursor.execute("SELECT id, val FROM unique_items WHERE val >= 5000 AND val <= 10000")
        rows = cursor.fetchall()
        assert len(rows) == 501
    rel_filter_duration = (time.perf_counter() - t0_rel_filter) / 10.0

    conn.close()

    return {
        "inner_join_sec": inner_join_duration,
        "inner_join_qps": 1.0 / inner_join_duration if inner_join_duration > 0 else 0.0,
        "left_join_sec": left_join_duration,
        "left_join_qps": 1.0 / left_join_duration if left_join_duration > 0 else 0.0,
        "unique_insert_sec": unique_insert_duration,
        "unique_insert_ops": num_unique_rows / unique_insert_duration if unique_insert_duration > 0 else 0.0,
        "rel_filter_sec": rel_filter_duration,
        "rel_filter_qps": 1.0 / rel_filter_duration if rel_filter_duration > 0 else 0.0,
    }


def main() -> None:
    print("=== Issue 382: SQLExecutor Algorithms & Hash Join Benchmark ===")
    res = run_benchmark()
    print(f"  INNER JOIN (1000 x 500): {res['inner_join_sec']:.4f} s ({res['inner_join_qps']:.2f} queries/s)")
    print(f"  LEFT JOIN  (1000 x 500): {res['left_join_sec']:.4f} s ({res['left_join_qps']:.2f} queries/s)")
    print(f"  UNIQUE INSERT (1500 rows): {res['unique_insert_sec']:.4f} s ({res['unique_insert_ops']:.1f} rows/s)")
    print(f"  REL FILTER (1500 rows):  {res['rel_filter_sec']:.4f} s ({res['rel_filter_qps']:.2f} queries/s)")


if __name__ == "__main__":
    main()
