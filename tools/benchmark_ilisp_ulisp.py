#!/usr/bin/env python3
"""
Trio Performance Benchmark Suite: ILisp vs ULisp AOT vs ULisp JIT
Conforms to Issue #515, DSN-31, DSN-33.

Continuously evaluates and compares execution latency, throughput, and memory
across three execution tiers:
  1. ILisp (Python-based R7RS Interpreter)
  2. ULisp AOT (Ahead-Of-Time compiled x86-64 native binary)
  3. ULisp JIT (Meta-tracing JIT accelerated in-process engine)
"""

import argparse
import datetime
import json
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
ULISP_DIR = ROOT_DIR / "ulisp"
BIN_DIR = ULISP_DIR / "bin"
BUILD_DIR = ULISP_DIR / "build"
RUNTIME_C = ULISP_DIR / "runtime.c"
ULISP_JIT_BIN = BIN_DIR / "ulisp-jit"
STAGE2_BIN = BUILD_DIR / "scheme-stage2"

PYTHON_BIN = sys.executable

# Standard Benchmarks
WORKLOADS: Dict[str, Dict[str, Any]] = {
    "fib_loop": {
        "title": "Iterative Fibonacci (fib 20)",
        "code": """(let loop ((i 0) (a 0) (b 1))
  (if (< i 20)
      (loop (+ i 1) b (+ a b))
      a))
""",
        "expected": "6765",
        "description": "Multi-variable state transition and sequential additions",
    },
    "fact_loop": {
        "title": "Iterative Factorial (fact 12)",
        "code": """(let loop ((n 12) (acc 1))
  (if (<= n 1)
      acc
      (loop (- n 1) (* acc n))))
""",
        "expected": "479001600",
        "description": "64-bit integer multiplication and accumulator updates",
    },
    "sum_loop": {
        "title": "Hot Loop Accumulation (5,000 iters)",
        "code": """(let loop ((i 0) (sum 0))
  (if (< i 5000)
      (loop (+ i 1) (+ sum i))
      sum))
""",
        "expected": "12497500",
        "description": "Named-let hot loop: tests JIT loop trace recording & branch prediction",
    },
    "poly_loop": {
        "title": "Polynomial Loop 3x^2+5x+7 (1,000 iters)",
        "code": """(let loop ((x 0) (acc 0))
  (if (< x 1000)
      (loop (+ x 1) (+ acc (+ (* 3 (* x x)) (+ (* 5 x) 7))))
      acc))
""",
        "expected": "1001005000",
        "description": "Heavy arithmetic instruction pipeline, register allocation, and loop optimization",
    },
    "tri_loop": {
        "title": "Triangular Sum (tri 500)",
        "code": """(let loop ((n 500) (acc 0))
  (if (<= n 0)
      acc
      (loop (- n 1) (+ acc n))))
""",
        "expected": "125250",
        "description": "Linear iteration counter decrement and accumulator addition",
    },
}


def extract_result(text: str) -> str:
    """Extract return value from output, handling ULisp-JIT banner and standard prints."""
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    for ln in lines:
        if ln.startswith("=> Result:"):
            return ln.replace("=> Result:", "").strip()
    return lines[-1] if lines else ""


def make_padded_env(base_env: Optional[Dict[str, str]] = None, target_total_bytes: int = 4096) -> Dict[str, str]:
    """
    Pad environment variables to a fixed length (Mytkowicz Stack Alignment Bias Elimination).
    Ensures consistent %rsp stack alignment across all benchmark iterations.
    """
    env = (base_env or os.environ).copy()
    env.pop("BENCHMARK_ENV_PAD", None)

    current_size = sum(len(k.encode("utf-8")) + len(v.encode("utf-8")) + 2 for k, v in env.items())
    pad_key = "BENCHMARK_ENV_PAD"
    prefix_len = len(pad_key) + 2

    if current_size + prefix_len < target_total_bytes:
        pad_len = target_total_bytes - (current_size + prefix_len)
        env[pad_key] = "X" * pad_len
    else:
        next_multiple = ((current_size + prefix_len + 4095) // 4096) * 4096
        pad_len = next_multiple - (current_size + prefix_len)
        env[pad_key] = "X" * pad_len
    return env


def run_with_perf(cmd: List[str], env: Dict[str, str]) -> Tuple[subprocess.CompletedProcess, Dict[str, Optional[int]]]:
    """
    Run command under Linux perf stat, parsing instructions, branch-misses, cycles, and page-faults.
    """
    perf_cmd = [
        "perf", "stat", "-x,",
        "-e", "instructions,branch-misses,cycles,page-faults",
        "--"
    ] + cmd
    res = subprocess.run(perf_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    perf_stats: Dict[str, Optional[int]] = {
        "instructions": None,
        "branch_misses": None,
        "cycles": None,
        "page_faults": None,
    }
    for line in res.stderr.splitlines():
        parts = line.split(",")
        if len(parts) >= 3:
            val_str = parts[0].strip()
            event = parts[2].strip()
            if val_str.isdigit():
                val = int(val_str)
                if event == "instructions":
                    perf_stats["instructions"] = val
                elif event == "branch-misses":
                    perf_stats["branch_misses"] = val
                elif event == "cycles":
                    perf_stats["cycles"] = val
                elif event == "page-faults":
                    perf_stats["page_faults"] = val
    return res, perf_stats


def run_ilisp(code: str, env_vars: Optional[Dict[str, str]] = None) -> Tuple[float, str]:
    """Execute code with ILisp (Python interpreter) using padded environment."""
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(code)
        f_path = f.name

    try:
        cmd = [PYTHON_BIN, "-m", "ilisp", "-p", f_path]
        env = make_padded_env()
        env["PYTHONPATH"] = str(ROOT_DIR)
        if env_vars:
            env.update(env_vars)

        t0 = time.perf_counter()
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        t1 = time.perf_counter()

        if res.returncode != 0:
            raise RuntimeError(f"ILisp execution failed (code {res.returncode}): {res.stderr}")

        output = extract_result(res.stdout)
        return (t1 - t0) * 1000.0, output
    finally:
        if os.path.exists(f_path):
            os.remove(f_path)


def compile_and_run_aot(code: str, compiler_path: Path) -> Tuple[float, float, str]:
    """Compile code to ELF binary using AOT compiler and execute it."""
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_in, tempfile.NamedTemporaryFile(
        "w", suffix=".s", delete=False
    ) as f_s, tempfile.NamedTemporaryFile("w", suffix="", delete=False) as f_exe:
        in_path = f_in.name
        s_path = f_s.name
        exe_path = f_exe.name

        # If using ulisp-jit in AOT mode, prepend (!compile)
        is_jit_bin = "ulisp-jit" in compiler_path.name
        if is_jit_bin:
            f_in.write("(!compile)\n" + code)
        else:
            f_in.write(code)
        f_in.flush()

    try:
        # AOT Compilation
        t_comp_0 = time.perf_counter()
        with open(s_path, "w") as out_s:
            comp_res = subprocess.run([str(compiler_path), in_path], stdout=out_s, stderr=subprocess.PIPE, text=True)
        if comp_res.returncode != 0:
            raise RuntimeError(f"AOT compilation failed: {comp_res.stderr}")

        gcc_res = subprocess.run(
            ["gcc", "-no-pie", "-O2", str(RUNTIME_C), s_path, "-o", exe_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if gcc_res.returncode != 0:
            raise RuntimeError(f"GCC linking failed: {gcc_res.stderr}")
        t_comp_1 = time.perf_counter()
        comp_ms = (t_comp_1 - t_comp_0) * 1000.0

        # Binary Execution
        env = make_padded_env()
        t_exec_0 = time.perf_counter()
        exec_res = subprocess.run([exe_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        t_exec_1 = time.perf_counter()
        exec_ms = (t_exec_1 - t_exec_0) * 1000.0

        if exec_res.returncode != 0:
            raise RuntimeError(f"AOT binary execution failed: {exec_res.stderr}")

        output = extract_result(exec_res.stdout)
        return comp_ms, exec_ms, output
    finally:
        for p in (in_path, s_path, exe_path):
            if os.path.exists(p):
                os.remove(p)


def run_ulisp_jit(code: str, jit_bin: Path) -> Tuple[float, str]:
    """Execute code using ULisp Meta-Tracing JIT engine with padded environment."""
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(code)
        f_path = f.name

    try:
        cmd = [str(jit_bin), f_path]
        env = make_padded_env()
        t0 = time.perf_counter()
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        t1 = time.perf_counter()

        if res.returncode != 0:
            raise RuntimeError(f"ULisp JIT execution failed (code {res.returncode}): {res.stderr}")

        output = extract_result(res.stdout)
        return (t1 - t0) * 1000.0, output
    finally:
        if os.path.exists(f_path):
            os.remove(f_path)


def measure_workload(
    name: str,
    spec: Dict[str, Any],
    iterations: int,
    compiler_path: Path,
    jit_bin: Path,
    use_perf: bool = False,
) -> Dict[str, Any]:
    """Run all 3 execution tiers for a given workload across multiple iterations."""
    code = spec["code"]
    expected = spec["expected"]
    env = make_padded_env()

    # 1. ILisp
    ilisp_times = []
    ilisp_out = ""
    for _ in range(iterations):
        ms, out = run_ilisp(code)
        ilisp_times.append(ms)
        ilisp_out = out

    # 2. ULisp AOT
    # We compile once for the binary execution benchmark, and measure pure binary execution iterations
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_in, tempfile.NamedTemporaryFile(
        "w", suffix=".s", delete=False
    ) as f_s, tempfile.NamedTemporaryFile("w", suffix="", delete=False) as f_exe:
        in_p, s_p, exe_p = f_in.name, f_s.name, f_exe.name
        is_jit_bin = "ulisp-jit" in compiler_path.name
        if is_jit_bin:
            f_in.write("(!compile)\n" + code)
        else:
            f_in.write(code)
        f_in.flush()

    perf_data: Dict[str, Any] = {}
    try:
        t0_comp = time.perf_counter()
        with open(s_p, "w") as out_s:
            subprocess.run([str(compiler_path), in_p], stdout=out_s, check=True)
        subprocess.run(["gcc", "-no-pie", "-O2", str(RUNTIME_C), s_p, "-o", exe_p], check=True)
        t1_comp = time.perf_counter()
        aot_comp_ms = (t1_comp - t0_comp) * 1000.0

        aot_exec_times = []
        aot_out = ""
        for _ in range(iterations):
            t0 = time.perf_counter()
            res = subprocess.run([exe_p], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
            t1 = time.perf_counter()
            if res.returncode != 0:
                raise RuntimeError(f"AOT run failed: {res.stderr}")
            aot_exec_times.append((t1 - t0) * 1000.0)
            aot_out = extract_result(res.stdout)

        # Linux perf profiling
        if use_perf:
            _, aot_perf = run_with_perf([exe_p], env=env)
            with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_jit_perf:
                f_jit_perf.write(code)
                jit_perf_p = f_jit_perf.name
            try:
                _, jit_perf = run_with_perf([str(jit_bin), jit_perf_p], env=env)
            finally:
                if os.path.exists(jit_perf_p):
                    os.remove(jit_perf_p)
            perf_data = {
                "ulisp_aot": aot_perf,
                "ulisp_jit": jit_perf,
            }
    finally:
        for p in (in_p, s_p, exe_p):
            if os.path.exists(p):
                os.remove(p)

    # 3. ULisp JIT
    jit_times = []
    jit_out = ""
    for _ in range(iterations):
        ms, out = run_ulisp_jit(code, jit_bin)
        jit_times.append(ms)
        jit_out = out

    # Verify correctness
    correctness = {
        "ilisp_valid": (ilisp_out == expected),
        "aot_valid": (aot_out == expected),
        "jit_valid": (jit_out == expected),
        "expected": expected,
        "actual_ilisp": ilisp_out,
        "actual_aot": aot_out,
        "actual_jit": jit_out,
    }

    ilisp_mean = statistics.mean(ilisp_times)
    aot_mean = statistics.mean(aot_exec_times)
    jit_mean = statistics.mean(jit_times)

    speedup_aot_vs_ilisp = ilisp_mean / aot_mean if aot_mean > 0 else 0.0
    speedup_jit_vs_ilisp = ilisp_mean / jit_mean if jit_mean > 0 else 0.0
    ratio_aot_vs_jit = jit_mean / aot_mean if aot_mean > 0 else 0.0

    return {
        "workload_id": name,
        "title": spec["title"],
        "description": spec["description"],
        "iterations": iterations,
        "correctness": correctness,
        "ilisp": {
            "mean_ms": ilisp_mean,
            "std_ms": statistics.stdev(ilisp_times) if len(ilisp_times) > 1 else 0.0,
            "min_ms": min(ilisp_times),
            "max_ms": max(ilisp_times),
        },
        "ulisp_aot": {
            "compile_ms": aot_comp_ms,
            "mean_ms": aot_mean,
            "std_ms": statistics.stdev(aot_exec_times) if len(aot_exec_times) > 1 else 0.0,
            "min_ms": min(aot_exec_times),
            "max_ms": max(aot_exec_times),
        },
        "ulisp_jit": {
            "mean_ms": jit_mean,
            "std_ms": statistics.stdev(jit_times) if len(jit_times) > 1 else 0.0,
            "min_ms": min(jit_times),
            "max_ms": max(jit_times),
        },
        "speedups": {
            "aot_vs_ilisp": speedup_aot_vs_ilisp,
            "jit_vs_ilisp": speedup_jit_vs_ilisp,
            "aot_vs_jit": ratio_aot_vs_jit,
        },
        "perf": perf_data,
    }


def generate_markdown_report(benchmark_data: Dict[str, Any]) -> str:
    """Generate rich GitHub Flavored Markdown report with tables and Mermaid diagrams."""
    timestamp = benchmark_data["timestamp"]
    system_info = benchmark_data["system"]
    results = benchmark_data["results"]
    has_perf = any(r.get("perf") for r in results)

    lines = []
    lines.append("# ILisp vs ULisp AOT vs ULisp JIT 3種実行系 性能評価レポート\n")
    lines.append(f"- **測定日時**: `{timestamp}`")
    lines.append(f"- **実行環境**: `{system_info['os']} {system_info['arch']}` (CPU: `{system_info['processor']}`)")
    lines.append(f"- **Python バージョン**: `{system_info['python_version']}`")
    lines.append(f"- **バイアス排除ハーネス**: Mytkowicz 4KB 環境変数パディング適用 (`BENCHMARK_ENV_PAD`)")
    if has_perf:
        lines.append("- **プロファイリング**: Linux `perf stat` 動的命令数 (`instructions`) & 分岐ミス計測有効")
    lines.append(f"- **評価対象**: ILisp (Interp), ULisp AOT (Native ELF), ULisp JIT (Meta-Tracing JIT)\n")
    lines.append("---\n")

    lines.append("## 1. 総合評価サマリー\n")
    if has_perf:
        lines.append(
            "| ワークロード | ILisp [Interp] (ms) | ULisp AOT (ms) | ULisp JIT (ms) | AOT命令数 (inst) | JIT命令数 (inst) | AOT加速比 | JIT加速比 | 整合性検証 |"
        )
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
        for r in results:
            w_title = r["title"]
            ilisp_m = f"{r['ilisp']['mean_ms']:.2f} ± {r['ilisp']['std_ms']:.2f}"
            aot_m = f"{r['ulisp_aot']['mean_ms']:.2f} ± {r['ulisp_aot']['std_ms']:.2f}"
            jit_m = f"{r['ulisp_jit']['mean_ms']:.2f} ± {r['ulisp_jit']['std_ms']:.2f}"
            p = r.get("perf", {})
            aot_inst = (
                f"{p.get('ulisp_aot', {}).get('instructions', 'N/A'):,}"
                if p.get("ulisp_aot", {}).get("instructions") is not None
                else "N/A"
            )
            jit_inst = (
                f"{p.get('ulisp_jit', {}).get('instructions', 'N/A'):,}"
                if p.get("ulisp_jit", {}).get("instructions") is not None
                else "N/A"
            )
            aot_speedup = f"**{r['speedups']['aot_vs_ilisp']:.1f}x**"
            jit_speedup = f"**{r['speedups']['jit_vs_ilisp']:.1f}x**"
            c = r["correctness"]
            is_ok = c["ilisp_valid"] and c["aot_valid"] and c["jit_valid"]
            status = "🟢 100% PASS" if is_ok else "🔴 FAIL"
            lines.append(
                f"| {w_title} | {ilisp_m} | {aot_m} | {jit_m} | {aot_inst} | {jit_inst} | {aot_speedup} | {jit_speedup} | {status} |"
            )
    else:
        lines.append(
            "| ワークロード | ILisp [Interp] (ms) | ULisp AOT (ms) | ULisp JIT (ms) | AOT加速比 (vs ILisp) | JIT加速比 (vs ILisp) | 整合性検証 |"
        )
        lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
        for r in results:
            w_title = r["title"]
            ilisp_m = f"{r['ilisp']['mean_ms']:.2f} ± {r['ilisp']['std_ms']:.2f}"
            aot_m = f"{r['ulisp_aot']['mean_ms']:.2f} ± {r['ulisp_aot']['std_ms']:.2f}"
            jit_m = f"{r['ulisp_jit']['mean_ms']:.2f} ± {r['ulisp_jit']['std_ms']:.2f}"
            aot_speedup = f"**{r['speedups']['aot_vs_ilisp']:.1f}x**"
            jit_speedup = f"**{r['speedups']['jit_vs_ilisp']:.1f}x**"
            c = r["correctness"]
            is_ok = c["ilisp_valid"] and c["aot_valid"] and c["jit_valid"]
            status = "🟢 100% PASS" if is_ok else "🔴 FAIL"
            lines.append(f"| {w_title} | {ilisp_m} | {aot_m} | {jit_m} | {aot_speedup} | {jit_speedup} | {status} |")

    lines.append("\n---\n")
    lines.append("## 2. ワークロード別詳細分析\n")

    for r in results:
        lines.append(f"### {r['title']} (`{r['workload_id']}`)\n")
        lines.append(f"- **概要**: {r['description']}")
        lines.append(f"- **反復回数**: {r['iterations']} 回")
        lines.append(
            f"- **期待値 / 実測値**: `{r['correctness']['expected']}` (ILisp: `{r['correctness']['actual_ilisp']}`, AOT: `{r['correctness']['actual_aot']}`, JIT: `{r['correctness']['actual_jit']}`)"
        )
        lines.append(f"- **AOT コンパイル所要時間**: `{r['ulisp_aot']['compile_ms']:.2f} ms`\n")

        lines.append("| 実行系 | 平均時間 (ms) | 最小値 (ms) | 最大値 (ms) | 標準偏差 (ms) |")
        lines.append("| :--- | :---: | :---: | :---: | :---: |")
        lines.append(
            f"| **ILisp** (Python) | {r['ilisp']['mean_ms']:.2f} | {r['ilisp']['min_ms']:.2f} | {r['ilisp']['max_ms']:.2f} | {r['ilisp']['std_ms']:.2f} |"
        )
        lines.append(
            f"| **ULisp AOT** (Native ELF) | {r['ulisp_aot']['mean_ms']:.2f} | {r['ulisp_aot']['min_ms']:.2f} | {r['ulisp_aot']['max_ms']:.2f} | {r['ulisp_aot']['std_ms']:.2f} |"
        )
        lines.append(
            f"| **ULisp JIT** (Meta-Tracing) | {r['ulisp_jit']['mean_ms']:.2f} | {r['ulisp_jit']['min_ms']:.2f} | {r['ulisp_jit']['max_ms']:.2f} | {r['ulisp_jit']['std_ms']:.2f} |"
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
    lines.append("## 3. アーキテクチャ階層と性能特性ダイアグラム\n")
    lines.append("```mermaid")
    lines.append("graph TD")
    lines.append(
        '    A["ILisp (Python Interp)"] -->|"AST解析・動的型付・GC管理"| Slow["オーバーヘッド大 (柔軟・デバッグ容易)"]'
    )
    lines.append(
        '    B["ULisp JIT (Meta-Tracing)"] -->|"ホットループ検知 & トレース即時コード化"| Med["適応型高スループット (動的最適化)"]'
    )
    lines.append(
        '    C["ULisp AOT (Native ELF)"] -->|"Nanopass AOT事前最適化 & 直接機械語"| Fast["極限低レイテンシ (ゼロオーバーヘッド)"]'
    )
    lines.append("```\n")

    return "\n".join(lines)


def check_regression(
    current_results: List[Dict[str, Any]],
    base_file: Path,
    threshold: float = 1.5,
) -> List[str]:
    """Compare current benchmark results against baseline JSON to detect regressions."""
    if not base_file.exists():
        return [f"Notice: Baseline file '{base_file}' does not exist. Skipping regression check."]

    with open(base_file, "r", encoding="utf-8") as f:
        base_data = json.load(f)

    base_map = {r["workload_id"]: r for r in base_data.get("results", [])}
    warnings = []

    for curr in current_results:
        wid = curr["workload_id"]
        if wid not in base_map:
            continue
        base = base_map[wid]

        # Check AOT execution
        curr_aot = curr["ulisp_aot"]["mean_ms"]
        base_aot = base["ulisp_aot"]["mean_ms"]
        if base_aot > 0 and curr_aot > base_aot * threshold:
            ratio = curr_aot / base_aot
            warnings.append(
                f"REGRESSION WARNING in {wid} (ULisp AOT): "
                f"Latency increased by {ratio:.2f}x ({base_aot:.2f}ms -> {curr_aot:.2f}ms)"
            )

        # Check JIT execution
        curr_jit = curr["ulisp_jit"]["mean_ms"]
        base_jit = base["ulisp_jit"]["mean_ms"]
        if base_jit > 0 and curr_jit > base_jit * threshold:
            ratio = curr_jit / base_jit
            warnings.append(
                f"REGRESSION WARNING in {wid} (ULisp JIT): "
                f"Latency increased by {ratio:.2f}x ({base_jit:.2f}ms -> {curr_jit:.2f}ms)"
            )

    return warnings


def main():
    parser = argparse.ArgumentParser(description="Benchmark Suite for ILisp, ULisp AOT, and ULisp JIT")
    parser.add_argument("--iterations", "-n", type=int, default=10, help="Number of benchmark iterations per workload")
    parser.add_argument(
        "--compiler", type=str, default="", help="Path to AOT compiler binary (default: scheme-stage2 or ulisp-jit)"
    )
    parser.add_argument(
        "--jit-bin", type=str, default="", help="Path to ulisp-jit binary (default: ulisp/bin/ulisp-jit)"
    )
    parser.add_argument(
        "--json-out", type=str, default="outputs/benchmarks/latest.json", help="Path to write JSON results"
    )
    parser.add_argument(
        "--markdown-out",
        type=str,
        default="outputs/benchmarks/benchmark_report.md",
        help="Path to write Markdown report",
    )
    parser.add_argument("--compare", type=str, default="", help="Baseline JSON file for regression comparison")
    parser.add_argument("--threshold", type=float, default=1.5, help="Regression threshold ratio (default: 1.5x)")
    parser.add_argument("--workloads", type=str, default="", help="Comma-separated list of workload IDs to run")
    parser.add_argument(
        "--perf",
        action="store_true",
        help="Enable Linux perf stat dynamic instruction and branch-miss profiling (Mytkowicz protocol)",
    )
    args = parser.parse_args()

    # Determine compiler binary
    compiler_path = Path(args.compiler) if args.compiler else None
    if not compiler_path or not compiler_path.exists():
        if ULISP_JIT_BIN.exists():
            compiler_path = ULISP_JIT_BIN
        elif STAGE2_BIN.exists():
            compiler_path = STAGE2_BIN
        else:
            raise FileNotFoundError(
                f"Neither {ULISP_JIT_BIN} nor {STAGE2_BIN} exists. Please run 'make -C ulisp jit' first."
            )

    jit_path = Path(args.jit_bin) if args.jit_bin else ULISP_JIT_BIN
    if not jit_path.exists():
        raise FileNotFoundError(f"ULisp JIT binary not found: {jit_path}. Please run 'make -C ulisp jit' first.")

    target_workloads = [w.strip() for w in args.workloads.split(",")] if args.workloads else list(WORKLOADS.keys())

    print("==========================================================================")
    print(" ILisp vs ULisp AOT vs ULisp JIT - Trio Performance Benchmark Suite")
    if args.perf:
        print(" [Mytkowicz Bias Elimination & Linux perf stat Profiling Enabled]")
    print("==========================================================================")
    print(f"Compiler (AOT) : {compiler_path}")
    print(f"JIT Engine     : {jit_path}")
    print(f"Iterations     : {args.iterations}")
    print(f"Target Tests   : {', '.join(target_workloads)}")
    print(f"Perf Profiling : {args.perf}")
    print("==========================================================================\n")

    results = []
    for wid in target_workloads:
        if wid not in WORKLOADS:
            print(f"Warning: Unknown workload '{wid}', skipping.")
            continue
        spec = WORKLOADS[wid]
        print(f"[*] Running: {spec['title']} ({args.iterations} iterations)...", end="", flush=True)
        res = measure_workload(wid, spec, args.iterations, compiler_path, jit_path, use_perf=args.perf)
        results.append(res)
        extra = ""
        if args.perf and res.get("perf"):
            aot_ins = res["perf"].get("ulisp_aot", {}).get("instructions")
            jit_ins = res["perf"].get("ulisp_jit", {}).get("instructions")
            extra = f" | Inst (AOT: {aot_ins:,} / JIT: {jit_ins:,})" if aot_ins and jit_ins else ""
        print(
            f" Done! [ILisp: {res['ilisp']['mean_ms']:.2f}ms | AOT: {res['ulisp_aot']['mean_ms']:.2f}ms | JIT: {res['ulisp_jit']['mean_ms']:.2f}ms{extra}]"
        )

    # System metadata
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    benchmark_data = {
        "timestamp": now_str,
        "system": {
            "os": platform.system(),
            "arch": platform.machine(),
            "processor": platform.processor() or "x86_64",
            "python_version": platform.python_version(),
        },
        "config": {
            "iterations": args.iterations,
            "compiler": str(compiler_path),
            "jit_bin": str(jit_path),
            "perf_enabled": args.perf,
        },
        "results": results,
    }

    # Output JSON
    if args.json_out:
        json_path = Path(args.json_out)
        json_path.parent.mkdir(parents=True, exist_ok=True)
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(benchmark_data, f, indent=2, ensure_ascii=False)
        print(f"\n[+] Saved structured benchmark JSON to: {json_path}")

        # Also store to history
        hist_dir = json_path.parent / "history"
        hist_dir.mkdir(parents=True, exist_ok=True)
        hist_file = hist_dir / f"benchmark_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(hist_file, "w", encoding="utf-8") as f:
            json.dump(benchmark_data, f, indent=2, ensure_ascii=False)
        print(f"[+] Saved historical snapshot to: {hist_file}")

    # Output Markdown
    if args.markdown_out:
        md_path = Path(args.markdown_out)
        md_path.parent.mkdir(parents=True, exist_ok=True)
        md_content = generate_markdown_report(benchmark_data)
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(md_content)
        print(f"[+] Saved Markdown evaluation report to: {md_path}")

    # Print Summary Table to stdout
    print("\n" + "=" * 80)
    print(" BENCHMARK RESULTS SUMMARY")
    print("=" * 80)
    if args.perf:
        header = f"{'Workload':<26} | {'ILisp (ms)':<12} | {'AOT (ms)':<12} | {'JIT (ms)':<12} | {'AOT Inst':<10} | {'JIT Inst':<10} | {'AOT Speedup':<10}"
        print(header)
        print("-" * len(header))
        for r in results:
            w_title = r["title"][:24]
            ilisp_s = f"{r['ilisp']['mean_ms']:.2f}"
            aot_s = f"{r['ulisp_aot']['mean_ms']:.2f}"
            jit_s = f"{r['ulisp_jit']['mean_ms']:.2f}"
            p = r.get("perf", {})
            aot_inst = f"{p.get('ulisp_aot', {}).get('instructions', 0):,}"
            jit_inst = f"{p.get('ulisp_jit', {}).get('instructions', 0):,}"
            aot_sp = f"{r['speedups']['aot_vs_ilisp']:.1f}x"
            print(f"{w_title:<26} | {ilisp_s:<12} | {aot_s:<12} | {jit_s:<12} | {aot_inst:<10} | {jit_inst:<10} | {aot_sp:<10}")
    else:
        header = f"{'Workload':<30} | {'ILisp (ms)':<14} | {'AOT (ms)':<14} | {'JIT (ms)':<14} | {'AOT Speedup':<12} | {'JIT Speedup':<12}"
        print(header)
        print("-" * len(header))
        for r in results:
            w_title = r["title"][:28]
            ilisp_s = f"{r['ilisp']['mean_ms']:.2f} ± {r['ilisp']['std_ms']:.2f}"
            aot_s = f"{r['ulisp_aot']['mean_ms']:.2f} ± {r['ulisp_aot']['std_ms']:.2f}"
            jit_s = f"{r['ulisp_jit']['mean_ms']:.2f} ± {r['ulisp_jit']['std_ms']:.2f}"
            aot_sp = f"{r['speedups']['aot_vs_ilisp']:.1f}x"
            jit_sp = f"{r['speedups']['jit_vs_ilisp']:.1f}x"
            print(f"{w_title:<30} | {ilisp_s:<14} | {aot_s:<14} | {jit_s:<14} | {aot_sp:<12} | {jit_sp:<12}")
    print("=" * 80)

    # Regression Check
    if args.compare:
        print("\n[*] Checking for performance regressions against baseline...")
        warnings = check_regression(results, Path(args.compare), threshold=args.threshold)
        if warnings:
            for w in warnings:
                print(f"[!] {w}")
            sys.exit(1)
        else:
            print("[+] No regressions detected. All workloads within performance threshold.")


if __name__ == "__main__":
    main()
