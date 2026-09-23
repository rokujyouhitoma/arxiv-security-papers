#!/usr/bin/env python3
"""
Benchmark for Parameterized SQL Queries and AST Caching.
Used to measure baseline and post-optimization performance for Issue 381:
Implement SQL parameterized AST cache and parser optimization.
"""

import time
from typing import Any, Dict


def bench_parameterized_crud(num_rows: int = 1000) -> Dict[str, Any]:
    import os
    import sys

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_dir = os.path.join(repo_root, "src")
    if src_dir not in sys.path:
        sys.path.insert(0, src_dir)

    from database import connect
    from database.sql.parser import clear_sql_parser_caches, parse_sql

    clear_sql_parser_caches()

    conn = connect(":memory:")
    cursor = conn.cursor()

    cursor.execute("""
        CREATE TABLE items (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL,
            category TEXT
        )
    """)

    # 1. Parameterized INSERT execution
    t0_insert = time.perf_counter()
    for i in range(1, num_rows + 1):
        cursor.execute(
            "INSERT INTO items (id, name, price, category) VALUES (?, ?, ?, ?)",
            (i, f"item_{i}", float(i * 1.5), "electronics"),
        )
    insert_duration = time.perf_counter() - t0_insert

    # Check cache info for parse_sql
    insert_cache_info = parse_sql.cache_info()

    # 2. Parameterized SELECT execution
    t0_select = time.perf_counter()
    for i in range(1, num_rows + 1):
        cursor.execute(
            "SELECT id, name, price FROM items WHERE id = ?",
            (i,),
        )
        row = cursor.fetchone()
        assert row is not None
    select_duration = time.perf_counter() - t0_select

    # 3. Parameterized executemany execution
    cursor.execute("""
        CREATE TABLE bulk_items (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL
        )
    """)
    bulk_data = [(i, f"bulk_{i}", float(i * 2.0)) for i in range(1, num_rows + 1)]
    t0_executemany = time.perf_counter()
    cursor.executemany(
        "INSERT INTO bulk_items (id, name, price) VALUES (?, ?, ?)",
        bulk_data,
    )
    executemany_duration = time.perf_counter() - t0_executemany

    final_cache_info = parse_sql.cache_info()
    conn.close()

    return {
        "num_rows": num_rows,
        "insert_duration_sec": insert_duration,
        "insert_qps": num_rows / insert_duration if insert_duration > 0 else 0.0,
        "select_duration_sec": select_duration,
        "select_qps": num_rows / select_duration if select_duration > 0 else 0.0,
        "executemany_duration_sec": executemany_duration,
        "executemany_qps": num_rows / executemany_duration if executemany_duration > 0 else 0.0,
        "cache_hits": final_cache_info.hits,
        "cache_misses": final_cache_info.misses,
        "cache_currsize": final_cache_info.currsize,
    }


def main() -> None:
    print("=== Issue 381: Parameterized SQL Query & AST Cache Benchmark ===")
    res = bench_parameterized_crud(num_rows=1000)
    print(f"  Rows processed:        {res['num_rows']}")
    print(f"  INSERT Total Time:     {res['insert_duration_sec']:.4f} s ({res['insert_qps']:.1f} ops/s)")
    print(f"  SELECT Total Time:     {res['select_duration_sec']:.4f} s ({res['select_qps']:.1f} ops/s)")
    print(f"  executemany Total Time:{res['executemany_duration_sec']:.4f} s ({res['executemany_qps']:.1f} ops/s)")
    print(f"  parse_sql Cache Hits:  {res['cache_hits']}")
    print(f"  parse_sql Cache Misses:{res['cache_misses']}")
    print(f"  parse_sql Cache Size:  {res['cache_currsize']}")


if __name__ == "__main__":
    main()
