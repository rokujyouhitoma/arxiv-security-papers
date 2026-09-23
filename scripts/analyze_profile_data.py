#!/usr/bin/env python3
"""
Analyzes PyNYTProf .out profile data for src/database.
"""

import os
import sys
from collections import defaultdict

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC_DIR = os.path.join(REPO_ROOT, "src")
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)


def main():
    from core.profiler.storage import ProfileStorage

    prof_path = os.path.join(REPO_ROOT, "outputs/profiling/database_bench.out")
    if not os.path.exists(prof_path):
        print(f"Profile not found: {prof_path}")
        return

    data = ProfileStorage.load(prof_path)
    meta = data.metadata
    print("=== PyNYTProf Profile Analysis for src/database ===")
    print(f"Python Version: {meta.python_version} on {meta.platform_info}")
    print(f"Total Time: {meta.total_time_ns / 1e9:.4f} s ({meta.total_time_ns:,} ns)")
    print(f"Subroutines recorded: {len(data.subroutines)}")
    print(f"Files recorded: {len(data.lines)}")

    # Module breakdown
    module_time = defaultdict(int)
    module_calls = defaultdict(int)
    db_subs = []

    for name, sub in data.subroutines.items():
        fn = sub.filename
        if "src/database" in fn or "database/" in fn or "core/structures/peg" in fn:
            db_subs.append(sub)
            # Find submodule
            parts = fn.split("/")
            if "database" in parts:
                idx = parts.index("database")
                submod = (
                    "/".join(parts[idx : idx + 2])
                    if idx + 1 < len(parts)
                    else "database"
                )
            elif "peg" in fn:
                submod = "core/structures/peg"
            else:
                submod = "other"
            module_time[submod] += sub.exclusive_time_ns
            module_calls[submod] += sub.calls

    print("\n--- Submodule Time Breakdown (Exclusive Time) ---")
    total_db_ns = sum(module_time.values()) or 1
    for mod, ns in sorted(module_time.items(), key=lambda x: x[1], reverse=True):
        print(
            f"  {mod:<30}: {ns / 1e6:8.2f} ms ({ns / total_db_ns * 100:5.1f}%) | {module_calls[mod]:8,d} calls"
        )

    # Top 20 Exclusive Time Subroutines in src/database & parser
    print("\n--- Top 20 Hotspots by Exclusive (Self) Time ---")
    sorted_by_exc = sorted(db_subs, key=lambda s: s.exclusive_time_ns, reverse=True)[
        :20
    ]
    for idx, s in enumerate(sorted_by_exc, 1):
        rel_path = (
            os.path.relpath(s.filename, REPO_ROOT)
            if os.path.isabs(s.filename)
            else s.filename
        )
        print(
            f" {idx:2d}. {s.name:<36} {s.exclusive_time_ns / 1e6:8.2f} ms | "
            f"calls: {s.calls:7,d} | {rel_path}:{s.first_line}"
        )

    # Top 20 Inclusive Time Subroutines
    print("\n--- Top 20 Functions by Inclusive Time ---")
    sorted_by_inc = sorted(db_subs, key=lambda s: s.inclusive_time_ns, reverse=True)[
        :20
    ]
    for idx, s in enumerate(sorted_by_inc, 1):
        rel_path = (
            os.path.relpath(s.filename, REPO_ROOT)
            if os.path.isabs(s.filename)
            else s.filename
        )
        print(
            f" {idx:2d}. {s.name:<36} {s.inclusive_time_ns / 1e6:8.2f} ms | "
            f"calls: {s.calls:7,d} | {rel_path}:{s.first_line}"
        )

    # Top 20 Call Counts
    print("\n--- Top 20 Functions by Call Count ---")
    sorted_by_calls = sorted(db_subs, key=lambda s: s.calls, reverse=True)[:20]
    for idx, s in enumerate(sorted_by_calls, 1):
        rel_path = (
            os.path.relpath(s.filename, REPO_ROOT)
            if os.path.isabs(s.filename)
            else s.filename
        )
        print(
            f" {idx:2d}. {s.name:<36} calls: {s.calls:8,d} | "
            f"exc: {s.exclusive_time_ns / 1e6:8.2f} ms | {rel_path}:{s.first_line}"
        )

    # Top 25 Hottest Source Lines in src/database
    line_entries = []
    for fn, lines in data.lines.items():
        if "src/database" in fn or "database/" in fn or "core/structures/peg" in fn:
            for lno, metric in lines.items():
                line_entries.append((metric.time_ns, metric.count, fn, lno))

    print("\n--- Top 25 Hottest Source Lines in src/database ---")
    line_entries.sort(key=lambda x: x[0], reverse=True)
    for idx, (t_ns, count, fn, lno) in enumerate(line_entries[:25], 1):
        rel_path = os.path.relpath(fn, REPO_ROOT) if os.path.isabs(fn) else fn
        # Try to read line content
        line_text = ""
        try:
            with open(fn, "r", encoding="utf-8", errors="replace") as f:
                all_lines = f.readlines()
                if 0 < lno <= len(all_lines):
                    line_text = all_lines[lno - 1].strip()
        except Exception:
            pass
        print(
            f" {idx:2d}. {t_ns / 1e6:8.2f} ms | count: {count:7,d} | {rel_path}:{lno}"
        )
        if line_text:
            print(f"      Code: {line_text[:80]}")


if __name__ == "__main__":
    main()
