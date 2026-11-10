#!/usr/bin/env python3
"""Concurrency Performance Regression Verification Script.

Compares benchmark results against baseline JSON to prevent performance regressions
in Synapse Concurrency Runtime (Issue #795).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict


def load_json(filepath: Path) -> Dict[str, Any]:
    if not filepath.exists():
        sys.stderr.write(f"Error: JSON file not found: {filepath}\n")
        sys.exit(2)
    with filepath.open("r", encoding="utf-8") as f:
        data: Dict[str, Any] = json.load(f)
        return data


def format_num(val: Any) -> str:
    if isinstance(val, (int, float)):
        return f"{val:,}"
    return str(val)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify Synapse concurrency performance against baseline."
    )
    parser.add_argument(
        "--current",
        type=Path,
        required=True,
        help="Path to current benchmark JSON output",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        required=True,
        help="Path to baseline benchmark JSON",
    )
    parser.add_argument(
        "--throughput-threshold",
        type=float,
        default=0.20,
        help="Max allowable throughput drop ratio (default: 0.20 = 20%%)",
    )
    parser.add_argument(
        "--spawn-threshold",
        type=float,
        default=0.50,
        help="Max allowable spawn time increase ratio (default: 0.50 = 50%%)",
    )

    args = parser.parse_args()

    current = load_json(args.current)
    baseline = load_json(args.baseline)

    failures: list[str] = []

    print("\n" + "=" * 70)
    print(" SYNAPSE CONCURRENCY PERFORMANCE REGRESSION AUDIT (Issue #795)")
    print("=" * 70)

    # 1. Throughput Audit (Must not drop > threshold)
    cur_tput = float(current.get("microtasks_throughput", 0))
    base_tput = float(baseline.get("microtasks_throughput", 1000000))
    min_allowable_tput = base_tput * (1.0 - args.throughput_threshold)

    tput_ratio = ((cur_tput - base_tput) / base_tput) * 100.0 if base_tput > 0 else 0.0

    print(f"  Throughput:   Current = {format_num(int(cur_tput))} tasks/sec")
    print(f"                Baseline = {format_num(int(base_tput))} tasks/sec ({tput_ratio:+.1f}%)")
    print(f"                Threshold = >= {format_num(int(min_allowable_tput))} tasks/sec (-{args.throughput_threshold * 100:.0f}%)")

    if cur_tput < min_allowable_tput:
        failures.append(
            f"Throughput regression: {cur_tput:.0f} < minimum {min_allowable_tput:.0f} tasks/sec ({tput_ratio:.1f}%)"
        )
    elif cur_tput < 1000000.0:
        failures.append(
            f"DoD absolute criteria violation: throughput {cur_tput:.0f} < 1,000,000 tasks/sec"
        )

    # 2. Spawn Time Audit (Must not increase > threshold)
    cur_spawn = float(current.get("microtasks_spawn_ms", 0))
    base_spawn = float(baseline.get("microtasks_spawn_ms", 100))
    max_allowable_spawn = base_spawn * (1.0 + args.spawn_threshold)

    spawn_ratio = ((cur_spawn - base_spawn) / base_spawn) * 100.0 if base_spawn > 0 else 0.0

    print(f"  Spawn Time:   Current = {cur_spawn:.0f} ms")
    print(f"                Baseline = {base_spawn:.0f} ms ({spawn_ratio:+.1f}%)")
    print(f"                Threshold = <= {max_allowable_spawn:.0f} ms (+{args.spawn_threshold * 100:.0f}%)")

    if cur_spawn > max_allowable_spawn:
        failures.append(
            f"Spawn time regression: {cur_spawn:.0f} ms > maximum {max_allowable_spawn:.0f} ms ({spawn_ratio:+.1f}%)"
        )
    elif cur_spawn > 250.0:
        failures.append(
            f"DoD absolute criteria violation: spawn time {cur_spawn:.0f} ms > 250 ms"
        )

    # 3. Status Audit
    cur_status = current.get("microtasks_status", "UNKNOWN")
    if cur_status != "PASS":
        failures.append(f"Benchmark self-reported status is {cur_status}")

    print("=" * 70)
    if failures:
        print(" [REGRESSION AUDIT FAILED]")
        for f_msg in failures:
            print(f"   - FAIL: {f_msg}")
        print("=" * 70 + "\n")
        return 1

    print(" [REGRESSION AUDIT PASSED] All metrics within strict DoD & baseline tolerances.")
    print("=" * 70 + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

