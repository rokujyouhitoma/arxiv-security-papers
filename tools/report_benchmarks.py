#!/usr/bin/env python3
"""Automated Performance Benchmark Report Generator.

Conforms to [DSN-33-06] Chapter 4 & Issue #903.
Generates comprehensive Japanese executive markdown summaries (outputs/benchmarks/benchmark_report.md)
integrating recent history snapshots and statistical regression analysis.
"""

from __future__ import annotations

import argparse
import datetime
import json
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional

ROOT_DIR = Path(__file__).resolve().parent.parent
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5MB DoS protection (CWE-400)
MAX_HISTORY_SNAPSHOTS = 10  # Max history snapshots to display in trend table


def validate_path(path_str: str) -> Path:
    """Validate and sanitize paths to prevent path traversal (CWE-22 / CWE-73)."""
    p = Path(path_str)
    resolved = (ROOT_DIR / p).resolve() if not p.is_absolute() else p.resolve()
    try:
        resolved.relative_to(ROOT_DIR)
    except ValueError:
        if not (resolved.is_relative_to(Path("/tmp")) and resolved.exists()):
            raise ValueError(f"Security Alert: Path {path_str} traverses outside repository root (CWE-22)")
    return resolved


def load_json_safe(file_path: Path) -> Optional[Dict[str, Any]]:
    """Safely load JSON file with size and error handling (CWE-400)."""
    if not file_path.exists():
        return None
    try:
        size = file_path.stat().st_size
        if size > MAX_FILE_SIZE_BYTES:
            print(f"Warning: File {file_path.name} exceeds size limit, skipping.", file=sys.stderr)
            return None
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Warning: Failed to parse {file_path.name}: {e}", file=sys.stderr)
        return None


def collect_history(history_dir: Path, limit: int = MAX_HISTORY_SNAPSHOTS) -> List[Dict[str, Any]]:
    """Collect recent historical benchmark snapshots sorted by timestamp descending."""
    if not history_dir.exists() or not history_dir.is_dir():
        return []

    files = sorted(history_dir.glob("benchmark_*.json"), key=lambda p: p.name, reverse=True)
    snapshots = []
    for f in files[:limit]:
        data = load_json_safe(f)
        if data and "results" in data:
            snapshots.append(data)
    return snapshots


def generate_japanese_markdown_report(
    latest_data: Dict[str, Any],
    history_data: List[Dict[str, Any]],
    regression_data: Optional[Dict[str, Any]] = None,
) -> str:
    """Generate complete Japanese Markdown report conforming to DSN-33-06 and relative link rules."""
    timestamp = latest_data.get("timestamp", datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    system_info = latest_data.get("system", {})
    config = latest_data.get("config", {})
    results = latest_data.get("results", [])

    has_perf = any(r.get("perf") for r in results)
    reg_workloads = {w["workload_id"]: w for w in regression_data.get("workloads", [])} if regression_data else {}

    lines: List[str] = []

    # Title & Metadata
    lines.append("# ILisp vs ULisp AOT vs ULisp JIT 3種実行系 継続的性能評価レポート\n")
    lines.append(f"- **測定日時**: `{timestamp}`")
    sys_os = system_info.get("os", "Linux")
    sys_arch = system_info.get("arch", "x86_64")
    sys_proc = system_info.get("processor", "x86_64")
    lines.append(f"- **実行環境**: `{sys_os} {sys_arch}` (CPU: `{sys_proc}`)")
    lines.append(f"- **Python バージョン**: `{system_info.get('python_version', platform_python())}`")
    lines.append("- **測定バイアス排除**: Mytkowicz 4KB 環境変数パディング適用 (`BENCHMARK_ENV_PAD`)")
    lines.append(f"- **評価反復回数**: `{config.get('iterations', 10)} 回`")
    if has_perf:
        lines.append("- **プロファイリング**: Linux `perf stat` 動的命令数 (`instructions`) & 分岐ミス計測有効")
    lines.append("- **評価対象**: ILisp (Python Interp), ULisp AOT (Nanopass Native ELF), ULisp JIT (Meta-Tracing JIT)\n")
    lines.append("---\n")

    # Section 1: Executive Summary
    lines.append("## 1. 総合評価エグゼクティブサマリー\n")
    if has_perf:
        lines.append(
            "| ワークロード | ILisp [Interp] (ms) | ULisp AOT (ms) | ULisp JIT (ms) | "
            "AOT命令数 (inst) | JIT命令数 (inst) | AOT加速比 | JIT加速比 | 整合性検証 | 退行判定 |"
        )
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
        for r in results:
            wid = r["workload_id"]
            w_title = r["title"]
            ilisp_m = f"{r['ilisp']['mean_ms']:.2f} ± {r['ilisp']['std_ms']:.2f}"
            aot_m = f"{r['ulisp_aot']['mean_ms']:.2f} ± {r['ulisp_aot']['std_ms']:.2f}"
            jit_m = f"{r['ulisp_jit']['mean_ms']:.2f} ± {r['ulisp_jit']['std_ms']:.2f}"
            p = r.get("perf", {})
            aot_ins_val = p.get("ulisp_aot", {}).get("instructions")
            jit_ins_val = p.get("ulisp_jit", {}).get("instructions")
            aot_inst = f"{aot_ins_val:,}" if aot_ins_val is not None else "N/A"
            jit_inst = f"{jit_ins_val:,}" if jit_ins_val is not None else "N/A"
            aot_sp = f"**{r['speedups']['aot_vs_ilisp']:.1f}x**"
            jit_sp = f"**{r['speedups']['jit_vs_ilisp']:.1f}x**"
            c = r["correctness"]
            is_ok = c["ilisp_valid"] and c["aot_valid"] and c["jit_valid"]
            c_status = "🟢 100% PASS" if is_ok else "🔴 FAIL"

            reg_status = "🟢 PASS"
            if wid in reg_workloads:
                st = reg_workloads[wid]["status"]
                reg_status = "🟢 PASS" if st == "PASS" else ("🟡 WARN" if st == "WARNING" else "🔴 REGRESSION")

            lines.append(
                f"| {w_title} | {ilisp_m} | {aot_m} | {jit_m} | {aot_inst} | "
                f"{jit_inst} | {aot_sp} | {jit_sp} | {c_status} | {reg_status} |"
            )
    else:
        lines.append(
            "| ワークロード | ILisp [Interp] (ms) | ULisp AOT (ms) | ULisp JIT (ms) | "
            "AOT加速比 (vs ILisp) | JIT加速比 (vs ILisp) | 整合性検証 | 退行判定 |"
        )
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
        for r in results:
            wid = r["workload_id"]
            w_title = r["title"]
            ilisp_m = f"{r['ilisp']['mean_ms']:.2f} ± {r['ilisp']['std_ms']:.2f}"
            aot_m = f"{r['ulisp_aot']['mean_ms']:.2f} ± {r['ulisp_aot']['std_ms']:.2f}"
            jit_m = f"{r['ulisp_jit']['mean_ms']:.2f} ± {r['ulisp_jit']['std_ms']:.2f}"
            aot_sp = f"**{r['speedups']['aot_vs_ilisp']:.1f}x**"
            jit_sp = f"**{r['speedups']['jit_vs_ilisp']:.1f}x**"
            c = r["correctness"]
            is_ok = c["ilisp_valid"] and c["aot_valid"] and c["jit_valid"]
            c_status = "🟢 100% PASS" if is_ok else "🔴 FAIL"

            reg_status = "🟢 PASS"
            if wid in reg_workloads:
                st = reg_workloads[wid]["status"]
                reg_status = "🟢 PASS" if st == "PASS" else ("🟡 WARN" if st == "WARNING" else "🔴 REGRESSION")

            lines.append(
                f"| {w_title} | {ilisp_m} | {aot_m} | {jit_m} | {aot_sp} | {jit_sp} | {c_status} | {reg_status} |"
            )

    lines.append("\n---\n")

    # Section 2: Statistical Regression Analysis
    lines.append("## 2. 統計的性能退行分析 (Welch's t-test Regression Analysis)\n")
    if regression_data:
        th = regression_data.get("threshold_percent", 5.0)
        pval_th = regression_data.get("p_value_threshold", 0.05)
        lines.append("- **検定モデル**: ウェルチの t 検定（Welch's t-test, 等分散性を仮定しない両標本検定）")
        lines.append(f"- **退行判定基準**: レイテンシ悪化率 $\\ge +{th:.1f}\\%$ かつ 統計的有意差 $p < {pval_th:.2f}$")
        overall_st = regression_data.get("status")
        verdict = (
            "🟢 合格 (No Regression)"
            if overall_st == "PASS"
            else ("🟡 注意 (Warning)" if overall_st == "WARNING" else "🔴 性能退行検知 (Regression Detected)")
        )
        lines.append(f"- **総合判定**: **{verdict}**\n")

        lines.append(
            "| ワークロード | 実行系 | ベースライン平均 (ms) | 今回平均 (ms) | 変化率 (%) | "
            "t 統計量 | 有意確率 p 値 | 判定 | 診断コメント |"
        )
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |")

        for w in regression_data.get("workloads", []):
            w_title = w["title"]
            for tier, res in w.get("tiers", {}).items():
                tier_label = "ULisp AOT" if tier == "ulisp_aot" else ("ULisp JIT" if tier == "ulisp_jit" else tier)
                b_mean = f"{res['base_mean_ms']:.2f}"
                c_mean = f"{res['cand_mean_ms']:.2f}"
                delta_str = f"{res['delta_percent']:+.1f}%"
                t_str = f"{res['t_statistic']:.2f}"
                p_str = f"{res['p_value']:.4f}"
                st = res["status"]
                st_icon = "🟢 PASS" if st == "PASS" else ("🟡 WARN" if st == "WARNING" else "🔴 REGRESSION")
                lines.append(
                    f"| {w_title} | {tier_label} | {b_mean} | {c_mean} | {delta_str} | "
                    f"{t_str} | {p_str} | {st_icon} | {res['reason']} |"
                )
    else:
        lines.append("※ 本実行では独立したベースライン比較データが指定されていないため、直近スナップショットをベースラインとして保持します。")

    lines.append("\n---\n")

    # Section 3: Historical Trend Table
    lines.append("## 3. 時系列トレンド推移 (Historical Trend Analysis)\n")
    if history_data:
        lines.append(f"直近 {len(history_data)} 回のベンチマーク実行におけるワークロード別レイテンシ推移（ULisp AOT / JIT）:\n")
        lines.append("| 測定日時 | ワークロード | AOT時間 (ms) | JIT時間 (ms) | AOT加速比 | JIT加速比 |")
        lines.append("| :--- | :--- | :---: | :---: | :---: | :---: |")
        for snap in history_data:
            s_time = snap.get("timestamp", "Unknown")
            for sr in snap.get("results", []):
                s_title = sr.get("title", sr.get("workload_id", ""))
                s_aot = f"{sr.get('ulisp_aot', {}).get('mean_ms', 0.0):.2f}"
                s_jit = f"{sr.get('ulisp_jit', {}).get('mean_ms', 0.0):.2f}"
                s_aot_sp = f"{sr.get('speedups', {}).get('aot_vs_ilisp', 0.0):.1f}x"
                s_jit_sp = f"{sr.get('speedups', {}).get('jit_vs_ilisp', 0.0):.1f}x"
                lines.append(f"| `{s_time}` | {s_title} | {s_aot} | {s_jit} | {s_aot_sp} | {s_jit_sp} |")
    else:
        lines.append("現在蓄積されている履歴スナップショットはありません。")

    lines.append("\n---\n")

    # Section 4: Workload Detail Breakdown
    lines.append("## 4. ワークロード別詳細分析\n")
    for r in results:
        lines.append(f"### {r['title']} (`{r['workload_id']}`)\n")
        lines.append(f"- **概要**: {r['description']}")
        lines.append(f"- **反復回数**: {r.get('iterations', 10)} 回")
        exp = r['correctness']['expected']
        act_i = r['correctness']['actual_ilisp']
        act_a = r['correctness']['actual_aot']
        act_j = r['correctness']['actual_jit']
        lines.append(f"- **期待値 / 実測値**: `{exp}` (ILisp: `{act_i}`, AOT: `{act_a}`, JIT: `{act_j}`)")
        lines.append(f"- **AOT コンパイル所要時間**: `{r['ulisp_aot']['compile_ms']:.2f} ms`\n")

        lines.append("| 実行系 | 平均時間 (ms) | 最小値 (ms) | 最大値 (ms) | 標準偏差 (ms) |")
        lines.append("| :--- | :---: | :---: | :---: | :---: |")
        lines.append(
            f"| **ILisp** (Python) | {r['ilisp']['mean_ms']:.2f} | {r['ilisp']['min_ms']:.2f} | "
            f"{r['ilisp']['max_ms']:.2f} | {r['ilisp']['std_ms']:.2f} |"
        )
        lines.append(
            f"| **ULisp AOT** (Native ELF) | {r['ulisp_aot']['mean_ms']:.2f} | {r['ulisp_aot']['min_ms']:.2f} | "
            f"{r['ulisp_aot']['max_ms']:.2f} | {r['ulisp_aot']['std_ms']:.2f} |"
        )
        lines.append(
            f"| **ULisp JIT** (Meta-Tracing) | {r['ulisp_jit']['mean_ms']:.2f} | {r['ulisp_jit']['min_ms']:.2f} | "
            f"{r['ulisp_jit']['max_ms']:.2f} | {r['ulisp_jit']['std_ms']:.2f} |"
        )
        lines.append("")

        p = r.get("perf", {})
        if p and (p.get("ulisp_aot") or p.get("ulisp_jit")):
            aot_p = p.get("ulisp_aot", {})
            jit_p = p.get("ulisp_jit", {})
            lines.append("#### Mytkowicz ハードウェア性能カウンタ (perf stat)")
            lines.append("| 指標 | ULisp AOT (Native) | ULisp JIT (Meta-Tracing) |")
            lines.append("| :--- | :---: | :---: |")
            for metric, label in [
                ("instructions", "動的実行命令数 (instructions)"),
                ("branch_misses", "分岐予測ミス (branch-misses)"),
                ("cycles", "実行サイクル数 (cycles)"),
                ("page_faults", "ページフォールト (page-faults)"),
            ]:
                v_aot = f"{aot_p.get(metric, 'N/A'):,}" if aot_p.get(metric) is not None else "N/A"
                v_jit = f"{jit_p.get(metric, 'N/A'):,}" if jit_p.get(metric) is not None else "N/A"
                lines.append(f"| **{label}** | {v_aot} | {v_jit} |")
            lines.append("")

    lines.append("---\n")

    # Section 5: Architecture Diagram
    lines.append("## 5. アーキテクチャ階層と性能特性ダイアグラム\n")
    lines.append("```mermaid")
    lines.append("graph TD")
    lines.append('    A["ILisp (Python Interp)"] -->|"AST解析・動的型付・GC管理"| Slow["オーバーヘッド大 (柔軟・デバッグ容易)"]')
    lines.append('    B["ULisp JIT (Meta-Tracing)"] -->|"ホットループ検知 & トレース即時コード化"| Med["適応型高スループット (動的最適化)"]')
    lines.append('    C["ULisp AOT (Native ELF)"] -->|"Nanopass AOT事前最適化 & 直接機械語"| Fast["極限低レイテンシ (ゼロオーバーヘッド)"]')
    lines.append("```\n")

    return "\n".join(lines)


def platform_python() -> str:
    """Return platform python version safely."""
    import platform
    return platform.python_version()


def main():
    parser = argparse.ArgumentParser(description="Automated Benchmark Report Generator")
    parser.add_argument(
        "--latest", "-l", type=str, default="outputs/benchmarks/latest.json", help="Path to latest JSON"
    )
    parser.add_argument(
        "--history-dir", "-H", type=str, default="outputs/benchmarks/history", help="Path to history directory"
    )
    parser.add_argument("--regression-json", "-r", type=str, default="", help="Path to regression analysis JSON")
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default="outputs/benchmarks/benchmark_report.md",
        help="Path to output Markdown file",
    )
    parser.add_argument(
        "--limit", type=int, default=MAX_HISTORY_SNAPSHOTS, help="Maximum history snapshots to include"
    )
    args = parser.parse_args()

    latest_path = validate_path(args.latest)
    latest_data = load_json_safe(latest_path)
    if not latest_data:
        print(f"[!] Error: Could not load latest benchmark JSON from {latest_path}", file=sys.stderr)
        sys.exit(1)

    hist_dir = validate_path(args.history_dir)
    history_data = collect_history(hist_dir, limit=args.limit)

    regression_data = None
    if args.regression_json:
        reg_path = validate_path(args.regression_json)
        regression_data = load_json_safe(reg_path)

    md_content = generate_japanese_markdown_report(latest_data, history_data, regression_data)

    out_path = validate_path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(md_content)

    print(f"[+] Successfully generated benchmark report: {out_path}")


if __name__ == "__main__":
    main()
