#!/usr/bin/env python3
"""
ULisp Performance Regression Verifier:
Compares the latest benchmark results against the canonical performance baseline.
Detects performance regressions, binary footprint bloat, and unexpected instruction growth.
Conforms to Issue #623 and DSN-33.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ULISP_DIR = Path(__file__).resolve().parent.parent
ROOT_DIR = ULISP_DIR.parent
DEFAULT_BASELINE = ROOT_DIR / "outputs" / "benchmarks" / "canonical_baseline.json"
DEFAULT_CURRENT = ROOT_DIR / "outputs" / "benchmarks" / "latest.json"
DEFAULT_REPORT = ULISP_DIR / "build" / "regression_report.md"


def get_system_metadata(data: Dict[str, Any]) -> str:
    env_parts = []
    if "os" in data:
        env_parts.append(str(data["os"]))
    if "arch" in data:
        env_parts.append(str(data["arch"]))
    if "gcc" in data:
        env_parts.append(f"GCC {data['gcc']}")
    if "cpu_model" in data:
        env_parts.append(str(data["cpu_model"]))
    return ", ".join(env_parts) if env_parts else "Unknown"


def verify_regression(
    baseline_path: Path,
    current_path: Path,
    threshold_latency_pct: float = 15.0,
    threshold_size_pct: float = 5.0,
    threshold_instructions_pct: float = 10.0,
    report_path: Optional[Path] = None,
    verbose: bool = False,
) -> int:
    if not baseline_path.exists():
        print(f"[ERROR] Baseline file not found: {baseline_path}", file=sys.stderr)
        print("Please run 'make bench_baseline' first to establish canonical metrics.", file=sys.stderr)
        return 1

    if not current_path.exists():
        print(f"[ERROR] Current benchmark file not found: {current_path}", file=sys.stderr)
        print("Please run 'make bench' first to produce latest benchmark metrics.", file=sys.stderr)
        return 1

    try:
        with open(baseline_path, "r", encoding="utf-8") as f:
            baseline_data = json.load(f)
    except Exception as e:
        print(f"[ERROR] Failed to parse baseline JSON ({baseline_path}): {e}", file=sys.stderr)
        return 1

    try:
        with open(current_path, "r", encoding="utf-8") as f:
            current_data = json.load(f)
    except Exception as e:
        print(f"[ERROR] Failed to parse current benchmark JSON ({current_path}): {e}", file=sys.stderr)
        return 1

    baseline_results: Dict[str, Dict[str, Any]] = {
        r["id"]: r for r in baseline_data.get("results", []) if "id" in r
    }
    current_results: List[Dict[str, Any]] = current_data.get("results", [])

    if not baseline_results:
        print("[ERROR] Baseline data contains no workload results.", file=sys.stderr)
        return 1
    if not current_results:
        print("[ERROR] Current benchmark data contains no workload results.", file=sys.stderr)
        return 1

    print("=" * 96)
    print(" ULisp Performance Regression Verification")
    print(f" Baseline: {baseline_path.name} ({get_system_metadata(baseline_data)})")
    print(f" Current : {current_path.name} ({get_system_metadata(current_data)})")
    print(f" Thresholds: Latency +{threshold_latency_pct:.1f}%, Binary Size +{threshold_size_pct:.1f}%")
    print("=" * 96)

    failures: List[str] = []
    checks: List[Dict[str, Any]] = []

    for curr in current_results:
        w_id = curr.get("id")
        w_name = curr.get("name", w_id)
        if w_id not in baseline_results:
            if verbose:
                print(f"[WARN] Workload '{w_id}' not found in baseline. Skipping.")
            continue

        base = baseline_results[w_id]

        # 1. Latency check (x86 mean_ms)
        curr_x86 = curr.get("x86", {})
        base_x86 = base.get("x86", {})
        curr_lat = curr_x86.get("mean_ms", 0.0)
        base_lat = base_x86.get("mean_ms", 0.0)

        lat_status = "PASS"
        lat_diff_pct = 0.0
        if base_lat > 0:
            lat_diff_pct = ((curr_lat - base_lat) / base_lat) * 100.0
            if lat_diff_pct > threshold_latency_pct:
                lat_status = "FAIL"
                failures.append(
                    f"Regression in {w_name}: Latency increased by {lat_diff_pct:+.2f}% "
                    f"({base_lat:.2f} ms -> {curr_lat:.2f} ms, limit: +{threshold_latency_pct:.1f}%)"
                )

        checks.append({
            "workload": w_name,
            "metric": "Latency (mean_ms)",
            "baseline": f"{base_lat:.2f} ms",
            "current": f"{curr_lat:.2f} ms",
            "delta": f"{lat_diff_pct:+.2f}%",
            "status": lat_status,
        })

        # 2. Binary size check (x86 size_bytes)
        curr_size = curr_x86.get("size_bytes", 0)
        base_size = base_x86.get("size_bytes", 0)
        size_status = "PASS"
        size_diff_pct = 0.0
        if base_size > 0:
            size_diff_pct = ((curr_size - base_size) / base_size) * 100.0
            if size_diff_pct > threshold_size_pct:
                size_status = "FAIL"
                failures.append(
                    f"Binary bloat in {w_name}: Size grew by {size_diff_pct:+.2f}% "
                    f"({base_size:,} B -> {curr_size:,} B, limit: +{threshold_size_pct:.1f}%)"
                )

        checks.append({
            "workload": w_name,
            "metric": "Binary Size",
            "baseline": f"{base_size:,} B",
            "current": f"{curr_size:,} B",
            "delta": f"{size_diff_pct:+.2f}%",
            "status": size_status,
        })

        # 3. Instruction count check (if perf data exists)
        curr_perf = curr.get("perf", {}).get("x86")
        base_perf = base.get("perf", {}).get("x86")
        if curr_perf and base_perf and "instructions" in curr_perf and "instructions" in base_perf:
            c_ins = curr_perf["instructions"]
            b_ins = base_perf["instructions"]
            if b_ins > 0:
                ins_diff_pct = ((c_ins - b_ins) / b_ins) * 100.0
                ins_status = "PASS"
                if ins_diff_pct > threshold_instructions_pct:
                    ins_status = "WARN"
                checks.append({
                    "workload": w_name,
                    "metric": "Instructions",
                    "baseline": f"{b_ins:,}",
                    "current": f"{c_ins:,}",
                    "delta": f"{ins_diff_pct:+.2f}%",
                    "status": ins_status,
                })

    # Print summary table
    print(f"{'Workload':<32} | {'Metric':<18} | {'Baseline':<12} | {'Current':<12} | {'Delta':<10} | {'Status'}")
    print("-" * 96)
    for c in checks:
        status_str = f"[\033[32mPASS\033[0m]" if c["status"] == "PASS" else (
            f"[\033[31mFAIL\033[0m]" if c["status"] == "FAIL" else f"[\033[33m{c['status']}\033[0m]"
        )
        print(f"{c['workload']:<32} | {c['metric']:<18} | {c['baseline']:<12} | {c['current']:<12} | {c['delta']:<10} | {status_str}")
    print("=" * 96)

    # Markdown Report Generation
    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        md_lines = [
            "# ULisp Continuous Performance Regression Verification Report",
            "",
            f"- **Baseline Reference**: `{baseline_path.name}`",
            f"- **Current Evaluation**: `{current_path.name}`",
            f"- **Latency Threshold**: `+{threshold_latency_pct:.1f}%`",
            f"- **Size Threshold**: `+{threshold_size_pct:.1f}%`",
            f"- **Overall Verification Status**: `{'PASS' if not failures else 'FAILED'}`",
            "",
            "## 1. 測定値差分検証結果",
            "",
            "| ワークロード | 評価項目 | 正典ベースライン | 最新測定値 | 乖離率 (Delta) | 判定結果 |",
            "|---|---|---|---|---|:---:|",
        ]
        for c in checks:
            badge = "✅ PASS" if c["status"] == "PASS" else ("❌ **FAIL**" if c["status"] == "FAIL" else "⚠️ WARN")
            md_lines.append(f"| **{c['workload']}** | {c['metric']} | {c['baseline']} | {c['current']} | `{c['delta']}` | {badge} |")

        if failures:
            md_lines.extend([
                "",
                "## 2. 検出された性能回帰 / 障害詳細",
                "",
            ])
            for f_msg in failures:
                md_lines.append(f"- ⚠️ **{f_msg}**")

        with open(report_path, "w", encoding="utf-8") as f:
            f.write("\n".join(md_lines) + "\n")
        print(f"[INFO] Regression report written to: {report_path}")

    if failures:
        print("\n\033[31m[REGRESSION DETECTED]\033[0m The following performance regressions were detected:")
        for f_msg in failures:
            print(f"  - ❌ {f_msg}")
        return 1

    print("\n\033[32m[VERIFICATION SUCCESS]\033[0m All benchmark metrics are within acceptable thresholds (0 regressions).")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Verify ULisp benchmark metrics against canonical baseline.")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE, help="Path to canonical baseline JSON")
    parser.add_argument("--current", type=Path, default=DEFAULT_CURRENT, help="Path to latest benchmark JSON")
    parser.add_argument("--threshold-latency", type=float, default=15.0, help="Max allowed latency increase percentage (default: 15.0)")
    parser.add_argument("--threshold-size", type=float, default=5.0, help="Max allowed binary size increase percentage (default: 5.0)")
    parser.add_argument("--threshold-instructions", type=float, default=10.0, help="Max allowed instruction count increase percentage (default: 10.0)")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT, help="Path to generate markdown regression report")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose diagnostics")

    args = parser.parse_args()
    ret = verify_regression(
        baseline_path=args.baseline,
        current_path=args.current,
        threshold_latency_pct=args.threshold_latency,
        threshold_size_pct=args.threshold_size,
        threshold_instructions_pct=args.threshold_instructions,
        report_path=args.report,
        verbose=args.verbose,
    )
    sys.exit(ret)


if __name__ == "__main__":
    main()
