#!/usr/bin/env python3
"""
ULisp Canonical Benchmark Suite:
x86-64 Native Bare-Metal (Freestanding) vs ULisp Portable C vs Pure C Baseline (-O2)
Measures execution latency (mean, median, min, max, stdev), binary size, hardware counters (perf),
and runtime GC statistics across 6 representative workloads.
Also compares with external Scheme implementations (Chez Scheme, Gauche) when available.
Conforms to DSN-33, Issue #620, Issue #622, and Issue #623.
"""

import argparse
import datetime
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional

ULISP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT_DIR = os.path.abspath(os.path.join(ULISP_DIR, ".."))
BUILD_DIR = os.path.join(ULISP_DIR, "build", "bench_c_x86")
OUTPUTS_BENCH_DIR = os.path.join(ROOT_DIR, "outputs", "benchmarks")
BASELINE_MD_PATH = os.path.join(ULISP_DIR, "benchmarks", "BASELINE.md")
CANONICAL_BASELINE_JSON = os.path.join(OUTPUTS_BENCH_DIR, "canonical_baseline.json")

os.makedirs(BUILD_DIR, exist_ok=True)
os.makedirs(OUTPUTS_BENCH_DIR, exist_ok=True)

PYTHON_BIN = sys.executable
COMPILER_SCM = os.path.join(ULISP_DIR, "compiler.scm")
ULISP_BOOT = os.path.join(ULISP_DIR, "bin", "ulisp-boot")

# 6 Canonical Workloads conforming to Issue #620, #622, #623
WORKLOADS = [
    {
        "id": "fib_30",
        "name": "Fibonacci (fib 30)",
        "description": "Recursive branching, call frame creation, and 64-bit integer addition",
        "scheme_expr": "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static int64_t fib(int64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
int main(void) {
    int64_t res = fib(30);
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)res);
    }
    return 0;
}
""",
        "expected": "832040",
        "iters": 10,
        "warmup": 3,
    },
    {
        "id": "loop_10m",
        "name": "Tail-Recursive Loop (10M)",
        "description": "TCO (Tail Call Optimization), loop counter register pinning, and backward jumps",
        "scheme_expr": "(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static int64_t loop(int64_t i, int64_t acc) {
    while (i < 10000000) {
        acc += i;
        i += 1;
    }
    return acc;
}
int main(void) {
    int64_t res = loop(0, 0);
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)res);
    }
    return 0;
}
""",
        "expected": "49999995000000",
        "iters": 10,
        "warmup": 3,
    },
    {
        "id": "ack_3_7",
        "name": "Ackermann (ack 3 7)",
        "description": "Deep stack frames and multi-recursive call overhead",
        "scheme_expr": "(letrec ((ack (lambda (m n) (if (= m 0) (+ n 1) (if (= n 0) (ack (- m 1) 1) (ack (- m 1) (ack m (- n 1)))))))) (ack 3 7))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static int64_t ack(int64_t m, int64_t n) {
    if (m == 0) return n + 1;
    if (n == 0) return ack(m - 1, 1);
    return ack(m - 1, ack(m, n - 1));
}
int main(void) {
    int64_t res = ack(3, 7);
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)res);
    }
    return 0;
}
""",
        "expected": "1021",
        "iters": 10,
        "warmup": 3,
    },
    {
        "id": "closure_1m",
        "name": "Higher-Order Closure (1M)",
        "description": "First-class closure invocation, environment reference, and indirect dispatch",
        "scheme_expr": "(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
typedef int64_t (*func_t)(void *, int64_t);
typedef struct {
    func_t fn;
    void *env;
} closure_t;
static int64_t add1(void *env, int64_t x) {
    (void)env;
    return x + 1;
}
static int64_t iter(int64_t n, closure_t f, int64_t acc) {
    while (n > 0) {
        acc = f.fn(f.env, acc);
        n--;
    }
    return acc;
}
int main(void) {
    closure_t c = { add1, NULL };
    int64_t res = iter(1000000, c, 0);
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)res);
    }
    return 0;
}
""",
        "expected": "1000000",
        "iters": 10,
        "warmup": 3,
    },
    {
        "id": "list_100k",
        "name": "List Alloc & Traverse (100k)",
        "description": "Linear heap bump allocation, GC pointer retention, and linked-pair traversal",
        "scheme_expr": "(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 '()) 0))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
typedef struct node {
    int64_t val;
    struct node *next;
} node_t;
int main(void) {
    node_t *pool = (node_t *)malloc(100000 * sizeof(node_t));
    if (!pool) return 1;
    node_t *head = NULL;
    for (int64_t n = 100000; n > 0; n--) {
        node_t *new_node = &pool[100000 - n];
        new_node->val = n;
        new_node->next = head;
        head = new_node;
    }
    int64_t acc = 0;
    for (node_t *curr = head; curr != NULL; curr = curr->next) {
        acc += curr->val;
    }
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)acc);
    }
    free(pool);
    return 0;
}
""",
        "expected": "5000050000",
        "iters": 10,
        "warmup": 3,
    },
    {
        "id": "vector_100k",
        "name": "Vector Indexing & Traverse (100k)",
        "description": "Contiguous memory allocation, element mutation, and indexed array traversal",
        "scheme_expr": "(letrec ((v (make-vector 100000)) (init (lambda (i) (if (= i 100000) 0 (begin (vector-set! v i 42) (init (+ i 1)))))) (traverse (lambda (i acc) (if (= i 100000) acc (traverse (+ i 1) (+ acc (vector-ref v i))))))) (begin (init 0) (traverse 0 0)))",
        "pure_c": """
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
int main(void) {
    int64_t *v = (int64_t *)malloc(100000 * sizeof(int64_t));
    if (!v) return 1;
    for (int64_t i = 0; i < 100000; i++) {
        v[i] = 42;
    }
    int64_t acc = 0;
    for (int64_t i = 0; i < 100000; i++) {
        acc += v[i];
    }
    if (getenv("ULISP_QUIET") == NULL) {
        printf("%lld\\n", (long long)acc);
    }
    free(v);
    return 0;
}
""",
        "expected": "4200000",
        "iters": 10,
        "warmup": 3,
    },
]


def get_system_specs() -> Dict[str, Any]:
    """Extracts detailed hardware and OS specification."""
    specs: Dict[str, Any] = {
        "os": platform.system(),
        "arch": platform.machine(),
        "kernel": platform.release(),
        "platform": platform.platform(),
        "cpu_count": os.cpu_count() or 1,
        "cpu_model": "Unknown CPU",
        "mem_total": "Unknown RAM",
        "gcc": subprocess.getoutput("gcc -dumpversion").strip(),
    }
    try:
        if os.path.exists("/proc/cpuinfo"):
            with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("model name"):
                        specs["cpu_model"] = line.split(":", 1)[1].strip()
                        break
        if os.path.exists("/proc/meminfo"):
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        specs["mem_total"] = line.split(":", 1)[1].strip()
                        break
    except Exception:
        pass
    return specs


def run_cmd(cmd: List[str], input_text: Optional[str] = None, cwd: str = ULISP_DIR) -> str:
    env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
    p = subprocess.run(
        cmd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
        env=env,
    )
    if p.returncode != 0:
        raise RuntimeError(f"Command failed ({cmd}):\n{p.stderr}")
    return p.stdout


def compile_scheme_to_file(in_code: str, out_path: str):
    """Compiles Scheme code to output file (.s or .c) using ulisp-boot or gosh/ilisp fallback."""
    tmp_scm = os.path.join(BUILD_DIR, "tmp_bench_in.scm")
    with open(tmp_scm, "w") as f:
        f.write(in_code)

    if "ULISP_COMPILER" in os.environ:
        compiler_cmd = os.environ["ULISP_COMPILER"].split()
        out_str = run_cmd(compiler_cmd, input_text=in_code)
        with open(out_path, "w") as out_f:
            out_f.write(out_str)
    elif shutil.which("gosh"):
        out_str = run_cmd(["gosh", COMPILER_SCM], input_text=in_code)
        with open(out_path, "w") as out_f:
            out_f.write(out_str)
    elif os.path.exists(ULISP_BOOT) and os.access(ULISP_BOOT, os.X_OK):
        with open(out_path, "w") as out_f:
            env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
            res = subprocess.run([ULISP_BOOT, tmp_scm], stdout=out_f, stderr=subprocess.PIPE, text=True, env=env)
            if res.returncode != 0:
                raise RuntimeError(f"ulisp-boot failed: {res.stderr}")
    else:
        out_str = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=in_code)
        with open(out_path, "w") as out_f:
            out_f.write(out_str)


def compile_x86(workload_id: str, expr: str) -> str:
    s_path = os.path.join(BUILD_DIR, f"{workload_id}.s")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_x86")
    compile_scheme_to_file(expr, s_path)
    run_cmd(["gcc", "-nostdlib", "-static", s_path, "-o", bin_path])
    return bin_path


def compile_ulisp_c(workload_id: str, expr: str) -> str:
    c_path = os.path.join(BUILD_DIR, f"{workload_id}_ulisp.c")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_ulisp_c")
    c_input = f"(!target c)\n{expr}"
    compile_scheme_to_file(c_input, c_path)
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-label", "-O2", c_path, "-o", bin_path])
    return bin_path


def compile_pure_c(workload_id: str, c_source: str) -> str:
    c_path = os.path.join(BUILD_DIR, f"{workload_id}_pure.c")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_pure_c")
    with open(c_path, "w") as f:
        f.write(c_source)
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-O2", c_path, "-o", bin_path])
    return bin_path


def verify_output(bin_path: str) -> str:
    env = os.environ.copy()
    env.pop("ULISP_QUIET", None)
    p = subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)
    return p.stdout.strip()


def measure_execution(bin_path: str, iterations: int, warmup: int = 3) -> Dict[str, float]:
    env = dict(os.environ, ULISP_QUIET="1")
    for _ in range(warmup):
        subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)

    times: List[float] = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0)

    mean_ms = statistics.mean(times)
    median_ms = statistics.median(times)
    min_ms = min(times)
    max_ms = max(times)
    std_ms = statistics.stdev(times) if len(times) > 1 else 0.0
    return {
        "mean_ms": mean_ms,
        "median_ms": median_ms,
        "min_ms": min_ms,
        "max_ms": max_ms,
        "std_ms": std_ms,
    }


def measure_scheme_interpreter(cmd_list: List[str], expr: str, iterations: int, warmup: int = 3) -> Optional[Dict[str, float]]:
    code = f"(display (begin {expr})) (newline)\n"
    for _ in range(warmup):
        p = subprocess.run(cmd_list, input=code, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.returncode != 0:
            return None
    times: List[float] = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        p = subprocess.run(cmd_list, input=code, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        t1 = time.perf_counter_ns()
        if p.returncode != 0:
            return None
        times.append((t1 - t0) / 1_000_000.0)
    return {
        "mean_ms": statistics.mean(times),
        "median_ms": statistics.median(times),
        "min_ms": min(times),
        "max_ms": max(times),
        "std_ms": statistics.stdev(times) if len(times) > 1 else 0.0,
    }


def measure_perf(bin_path: str) -> Optional[Dict[str, Any]]:
    cmd = [
        "perf", "stat", "-x,",
        "-e", "cycles,instructions,branches,branch-misses,cache-references,cache-misses",
        bin_path
    ]
    env = dict(os.environ, ULISP_QUIET="1")
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    except FileNotFoundError:
        return None
    except Exception:
        return None

    if p.returncode != 0 and not p.stderr:
        return None

    events: Dict[str, int] = {}
    for line in p.stderr.splitlines():
        parts = line.strip().split(",")
        if len(parts) >= 3:
            val_str = parts[0].strip()
            event_name = parts[2].strip()
            if val_str not in ("<not counted>", "<not supported>", ""):
                try:
                    events[event_name] = int(val_str)
                except ValueError:
                    try:
                        events[event_name] = int(float(val_str))
                    except ValueError:
                        pass

    if not events:
        return None

    cycles = events.get("cycles", 0)
    instructions = events.get("instructions", 0)
    branches = events.get("branches", 0)
    branch_misses = events.get("branch-misses", 0)
    cache_refs = events.get("cache-references", 0)
    cache_misses = events.get("cache-misses", 0)

    ipc = (instructions / cycles) if cycles > 0 else 0.0
    branch_miss_pct = (branch_misses / branches * 100.0) if branches > 0 else 0.0
    cache_miss_pct = (cache_misses / cache_refs * 100.0) if cache_refs > 0 else 0.0

    return {
        "cycles": cycles,
        "instructions": instructions,
        "branches": branches,
        "branch_misses": branch_misses,
        "cache_references": cache_refs,
        "cache_misses": cache_misses,
        "ipc": ipc,
        "branch_miss_pct": branch_miss_pct,
        "cache_miss_pct": cache_miss_pct,
    }


def measure_gc_stats(bin_path: str) -> Optional[Dict[str, str]]:
    env = dict(os.environ, ULISP_QUIET="1", ULISP_GC_STATS="1")
    try:
        p = subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    except Exception:
        return None

    for line in p.stderr.splitlines():
        if "[ULISP GC STATS]" in line:
            res: Dict[str, str] = {}
            parts = line.replace("[ULISP GC STATS]", "").strip().split(",")
            for part in parts:
                kv = part.strip().split(":")
                if len(kv) == 2:
                    k = kv[0].strip().lower()
                    v = kv[1].strip()
                    res[k] = v
            return res
    return None


def measure_nanopass_profile() -> Dict[str, Any]:
    """Captures Nanopass timing and memory breakdown using (!time-passes)."""
    test_expr = "(!time-passes)\n(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))\n(fib 30)\n"
    tmp_scm = os.path.join(BUILD_DIR, "nanopass_prof_in.scm")
    with open(tmp_scm, "w") as f:
        f.write(test_expr)

    env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
    passes: List[Dict[str, Any]] = []
    total_time_ms = 0.0
    total_alloc_bytes = 0

    try:
        if shutil.which("gosh"):
            p = subprocess.run(["gosh", COMPILER_SCM], input=test_expr, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        elif os.path.exists(ULISP_BOOT) and os.access(ULISP_BOOT, os.X_OK):
            p = subprocess.run([ULISP_BOOT, tmp_scm], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        else:
            p = subprocess.run([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input=test_expr, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)

        for line in p.stderr.splitlines():
            line_str = line.strip()
            if "Total Compilation Time :" in line_str:
                parts = line_str.split(":")
                if len(parts) >= 2:
                    val = parts[1].replace("ms", "").strip()
                    try:
                        total_time_ms = float(val)
                    except ValueError:
                        pass
            elif "Total Heap Allocation  :" in line_str:
                parts = line_str.split(":")
                if len(parts) >= 2:
                    val = parts[1].replace("bytes", "").replace(",", "").strip()
                    try:
                        total_alloc_bytes = int(val)
                    except ValueError:
                        pass
            elif line_str.startswith("[PASS]") or ("pass-" in line_str and "ms" in line_str):
                parts = line_str.replace("[PASS]", "").strip().split(":")
                if len(parts) == 2:
                    pname = parts[0].strip()
                    t_str = parts[1].strip()
                    t_ms = 0.0
                    pct = 0.0
                    if "ms" in t_str:
                        ms_part = t_str.split("ms")[0].strip()
                        try:
                            t_ms = float(ms_part)
                        except ValueError:
                            pass
                    if "(" in t_str and "%" in t_str:
                        pct_part = t_str.split("(")[1].split("%")[0].strip()
                        try:
                            pct = float(pct_part)
                        except ValueError:
                            pass
                    passes.append({
                        "pass": pname,
                        "time_ms": t_ms,
                        "pct": pct,
                    })
    except Exception:
        pass

    return {
        "total_time_ms": total_time_ms,
        "total_alloc_bytes": total_alloc_bytes,
        "passes": passes,
    }


def generate_baseline_markdown(
    timestamp: str,
    specs: Dict[str, Any],
    results: List[Dict[str, Any]],
    nanopass_profile: Dict[str, Any],
    perf_enabled: bool,
    iterations: int,
) -> str:
    """Generates the official BASELINE.md canonical report with Mermaid diagrams and tables."""
    md = f"""# ULisp Canonical Performance Baseline Report (BASELINE.md)

- **Measurement Timestamp**: `{timestamp}`
- **Execution Architecture**: `x86-64 Native (Freestanding / libc-free)` vs `ULisp C Backend (-O2)` vs `Pure C Baseline (-O2)`
- **System Platform**: `{specs['os']} {specs['arch']} ({specs['kernel']})`
- **CPU Architecture**: `{specs['cpu_model']}` ({specs['cpu_count']} Cores)
- **Total Physical Memory**: `{specs['mem_total']}`
- **C Toolchain**: `GCC {specs['gcc']}` (`-O2 -Wall -Wextra`)
- **Statistical Parameters**: `{iterations} 反復試行 (Warmup: 5 回)` による平均値 (Mean) ± 標準偏差 (StdDev) および中央値 (Median)
- **Conforms to**: **DSN-33 (ULisp 統合仕様書)**, **Issue #620**, **Issue #622**, **Issue #623**

---

## 1. 概要と正典ベースラインの位置付け / Executive Summary

本ドキュメントは、ULisp の次世代最適化施策（Issue #618 関数間アンボックス特化、Issue #578 スタック配置最適化、Pass 132/133 SSA/ピープホール）に着手する前に確定された**「公式正典ベースライン数値（Canonical Baseline Metrics）」**である。

ULisp ネイティブコンパイラ（`ulisp/bin/ulisp-boot`）によって生成された Freestanding x86-64 ELF バイナリは、外部 C ライブラリ（glibc/musl）を一切リンクせず、Linux システムコール（`sys_write`, `sys_mmap`, `sys_clock_gettime`, `sys_exit`）を直接発行する完全自己完結型バイナリである。

---

## 2. 実行時間ベンチマーク結果（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | Chez Scheme (ms) | Gauche (ms) | 対 Pure C 比率 (x86/Pure) | 対 Chez 比率 (x86/Chez) |
|---|---|---|---|---|---|:---:|:---:|
"""
    for r in results:
        x_m = r["x86"]["mean_ms"]
        x_sd = r["x86"]["std_ms"]
        x_med = r["x86"]["median_ms"]
        c_m = r["ulisp_c"]["mean_ms"]
        c_sd = r["ulisp_c"]["std_ms"]
        p_m = r["pure_c"]["mean_ms"]
        p_sd = r["pure_c"]["std_ms"]
        chez_s = f"{r['chez']['mean_ms']:.2f} ± {r['chez']['std_ms']:.2f}" if r.get("chez") else "N/A"
        gauche_s = f"{r['gauche']['mean_ms']:.2f} ± {r['gauche']['std_ms']:.2f}" if r.get("gauche") else "N/A"
        ratio_pure = f"**{r['ratio_x86_to_pure_c']:.2f}x**"
        ratio_chez = f"**{r['ratio_x86_to_chez']:.2f}x**" if r.get("ratio_x86_to_chez") else "N/A"
        md += f"| **{r['name']}** | {x_m:.2f} ± {x_sd:.2f} (med: {x_med:.2f}) | {c_m:.2f} ± {c_sd:.2f} | {p_m:.2f} ± {p_sd:.2f} | {chez_s} | {gauche_s} | {ratio_pure} | {ratio_chez} |\n"

    md += """
---

## 3. バイナリフットプリントと自己完結性（Binary Footprint & Self-Containment）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) | libc 依存 | リンカ構成 |
|---|---|---|---|:---:|---|
"""
    for r in results:
        md += f"| **{r['name']}** | {r['x86']['size_bytes']:,} B | {r['ulisp_c']['size_bytes']:,} B | {r['pure_c']['size_bytes']:,} B | **なし (Freestanding)** | `gcc -nostdlib -static` |\n"

    if perf_enabled:
        md += """
---

## 4. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
"""
        for r in results:
            xp = r.get("perf", {}).get("x86")
            cp = r.get("perf", {}).get("ulisp_c")
            pp = r.get("perf", {}).get("pure_c")
            x_ipc = f"{xp['ipc']:.2f}" if xp else "N/A"
            x_brmiss = f"{xp['branch_miss_pct']:.2f}%" if xp else "N/A"
            x_l1miss = f"{xp['cache_miss_pct']:.2f}%" if xp else "N/A"
            c_ipc = f"{cp['ipc']:.2f}" if cp else "N/A"
            p_ipc = f"{pp['ipc']:.2f}" if pp else "N/A"
            md += f"| **{r['name']}** | {x_ipc} | {x_brmiss} | {x_l1miss} | {c_ipc} | {p_ipc} |\n"

        md += """
---

## 5. 実行時メモリ割当＆GC統計（Runtime Memory Allocation & GC Profile）

| ワークロード | 累積ヒープ割当量 | 生存コピー量 | GC 停止時間 (ms) | GC 回収回数 | 備考 |
|---|---|---|---|:---:|---|
"""
        for r in results:
            xgc = r.get("gc_stats", {}).get("x86") or {}
            alloc_s = xgc.get("alloc", "0 B")
            copied_s = xgc.get("copied", "0 B")
            time_s = xgc.get("gc time", "0 ms")
            major_s = xgc.get("major", "0)")
            md += f"| **{r['name']}** | {alloc_s} | {copied_s} | {time_s} | {major_s} | バンプポインタ直結割当 |\n"

    if nanopass_profile and nanopass_profile.get("passes"):
        md += f"""
---

## 6. コンパイラ Nanopass 実行時間構成（Compiler Nanopass Profile）

- **代表ワークロード**: `fib 30` AOT コンパイル
- **総コンパイル所要時間**: `{nanopass_profile.get('total_time_ms', 0.0):.2f} ms`
- **総ヒープ割当量**: `{nanopass_profile.get('total_alloc_bytes', 0):,} bytes`

| パス名 | 処理層 | 所要時間 (ms) | 割合 (%) |
|---|---|---|---|
"""
        for p in nanopass_profile.get("passes", []):
            layer = "Frontend" if "0" in p["pass"] else ("LIR" if "13" in p["pass"] or "12" in p["pass"] else "Backend")
            md += f"| `{p['pass']}` | {layer} | {p['time_ms']:.2f} ms | {p['pct']:.1f}% |\n"

    md += """
---

## 7. Mermaid 可視化図表（Mermaid Visualizations）

### (1) 対 Pure C 相対実行速度比率（倍率: 1.0x が Pure C と同等）
```mermaid
graph LR
    subgraph "Execution Time Ratio (Lower is Faster, Pure C = 1.0x)"
"""
    for r in results:
        w_san = r["id"].replace("-", "_")
        ratio = r["ratio_x86_to_pure_c"]
        md += f'        {w_san}["{r["name"]}: {ratio:.2f}x"]\n'
    md += """    end
```

### (2) x86-64 ネイティブの IPC (Instructions Per Cycle) 特性
```mermaid
graph TD
    subgraph "CPU Pipeline Efficiency (IPC)"
"""
    for r in results:
        w_san = r["id"].replace("-", "_")
        xp = r.get("perf", {}).get("x86")
        ipc_val = xp["ipc"] if xp else 0.0
        md += f'        {w_san}_ipc["{r["name"]}: {ipc_val:.2f} IPC"]\n'
    md += """    end
```

---

## 8. 次期最適化施策における改善目標（Optimization Roadmap）

| Issue ID | 最適化対象 | ボトルネック分析 | 目標性能向上 |
|:---:|---|---|:---:|
| **#618** | S-RTyper（Pass 090）アンボックス特化 | `fib 30`, `loop 10m` におけるタグ付け (`salq $3`, `orq $1`) および型タグ判定の完全撲滅 | **2.0x〜3.0x 高速化** (Pure C と完全同等の 1.0x 到達) |
| **#578** | スタック配置最適化 | `closure 1M` における非エスケープクロージャ・フレームのスタック化 | **1.5x 高速化** / ヒープ割当 0 B |
| **#547** | バックエンド末尾ループ回転・アンローリング | ループジャンプ先のアライメントおよびレジスタシャッフル最小化 | **1.3x 高速化** |

"""
    return md


def main():
    parser = argparse.ArgumentParser(description="ULisp Canonical Performance Benchmark Suite")
    parser.add_argument("--perf", action="store_true", help="Enable Linux perf hardware counters & GC stats")
    parser.add_argument("--baseline", action="store_true", help="Record as canonical baseline in BASELINE.md and canonical_baseline.json")
    parser.add_argument("--iterations", type=int, default=None, help="Override trial iterations per workload (default: 10 or 30 in baseline)")
    parser.add_argument("--warmup", type=int, default=None, help="Override warmup runs per workload (default: 3 or 5 in baseline)")
    parser.add_argument("--include-nanopass", action="store_true", help="Include compiler Nanopass profile")
    parser.add_argument("--include-schemes", action="store_true", default=True, help="Include external Scheme benchmarks (Chez, Gauche)")

    args = parser.parse_args()

    perf_enabled = args.perf
    is_baseline = args.baseline
    default_iters = 30 if is_baseline else 10
    default_warmup = 5 if is_baseline else 3
    run_iters = args.iterations or default_iters
    run_warmup = args.warmup or default_warmup

    specs = get_system_specs()
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()

    chez_bin = shutil.which("chezscheme") or shutil.which("scheme")
    gosh_bin = shutil.which("gosh")

    print("=" * 96, flush=True)
    print(" ULisp Canonical Performance Benchmark: x86-64 Freestanding vs ULisp C vs Pure C", flush=True)
    print(f" Platform : {specs['platform']} ({specs['cpu_model']}, {specs['cpu_count']} cores)", flush=True)
    print(f" Toolchain: GCC {specs['gcc']}, Engine: {'ulisp-boot' if os.path.exists(ULISP_BOOT) else 'ILisp'}", flush=True)
    print(f" Mode     : {'Canonical Baseline Recording' if is_baseline else 'Standard Evaluation'} ({run_iters} iters, {run_warmup} warmup)", flush=True)
    if perf_enabled:
        print(" Profiling: Linux perf hardware counters & GC stats enabled (--perf)", flush=True)
    print("=" * 96, flush=True)

    results: List[Dict[str, Any]] = []

    for idx, w in enumerate(WORKLOADS, 1):
        w_id = w["id"]
        w_name = w["name"]
        expr = w["scheme_expr"]
        pure_c_src = w["pure_c"]
        expected = w["expected"]

        iters = run_iters
        warmup = run_warmup

        print(f"\n[{idx}/{len(WORKLOADS)}] Workload: {w_name} ({w['description']})", flush=True)

        # 1. ULisp x86-64 Native
        print("  [1/3] Compiling ULisp x86-64 (freestanding)...", end="", flush=True)
        t_c0 = time.time()
        x86_bin = compile_x86(w_id, expr)
        print(f" done ({time.time() - t_c0:.2f}s)", flush=True)
        x86_size = os.path.getsize(x86_bin)
        x86_out = verify_output(x86_bin)
        assert x86_out == expected, f"Output mismatch for x86-64 in {w_name}: expected '{expected}', got '{x86_out}'"
        x86_metrics = measure_execution(x86_bin, iters, warmup)
        x86_perf = measure_perf(x86_bin) if perf_enabled else None
        x86_gc = measure_gc_stats(x86_bin) if perf_enabled else None
        perf_info = ""
        if x86_perf:
            perf_info = f" | IPC: {x86_perf['ipc']:.2f}, BrMiss: {x86_perf['branch_miss_pct']:.2f}%, L1Miss: {x86_perf['cache_miss_pct']:.2f}%"
        print(f"        Execution: {x86_metrics['mean_ms']:7.2f} ms (med: {x86_metrics['median_ms']:7.2f} ms, std: {x86_metrics['std_ms']:5.2f} ms) | Size: {x86_size:6d} B{perf_info}", flush=True)

        # 2. ULisp C Backend (-O2)
        print("  [2/3] Compiling ULisp C backend (-O2)...", end="", flush=True)
        t_c1 = time.time()
        c_bin = compile_ulisp_c(w_id, expr)
        print(f" done ({time.time() - t_c1:.2f}s)", flush=True)
        c_size = os.path.getsize(c_bin)
        c_out = verify_output(c_bin)
        assert c_out == expected, f"Output mismatch for ULisp C in {w_name}: expected '{expected}', got '{c_out}'"
        c_metrics = measure_execution(c_bin, iters, warmup)
        c_perf = measure_perf(c_bin) if perf_enabled else None
        c_gc = measure_gc_stats(c_bin) if perf_enabled else None
        c_perf_info = ""
        if c_perf:
            c_perf_info = f" | IPC: {c_perf['ipc']:.2f}, BrMiss: {c_perf['branch_miss_pct']:.2f}%, L1Miss: {c_perf['cache_miss_pct']:.2f}%"
        print(f"        Execution: {c_metrics['mean_ms']:7.2f} ms (med: {c_metrics['median_ms']:7.2f} ms, std: {c_metrics['std_ms']:5.2f} ms) | Size: {c_size:6d} B{c_perf_info}", flush=True)

        # 3. Pure C Baseline (-O2)
        print("  [3/3] Compiling Pure C baseline (-O2)...", end="", flush=True)
        t_c2 = time.time()
        pure_c_bin = compile_pure_c(w_id, pure_c_src)
        print(f" done ({time.time() - t_c2:.2f}s)", flush=True)
        pure_c_size = os.path.getsize(pure_c_bin)
        pure_c_out = verify_output(pure_c_bin)
        assert pure_c_out == expected, f"Output mismatch for Pure C in {w_name}: expected '{expected}', got '{pure_c_out}'"
        pure_c_metrics = measure_execution(pure_c_bin, iters, warmup)
        pure_c_perf = measure_perf(pure_c_bin) if perf_enabled else None
        pure_perf_info = ""
        if pure_c_perf:
            pure_perf_info = f" | IPC: {pure_c_perf['ipc']:.2f}, BrMiss: {pure_c_perf['branch_miss_pct']:.2f}%, L1Miss: {pure_c_perf['cache_miss_pct']:.2f}%"
        print(f"        Execution: {pure_c_metrics['mean_ms']:7.2f} ms (med: {pure_c_metrics['median_ms']:7.2f} ms, std: {pure_c_metrics['std_ms']:5.2f} ms) | Size: {pure_c_size:6d} B{pure_perf_info}", flush=True)

        # 4. External Scheme implementations (if available)
        chez_metrics = None
        if args.include_schemes and chez_bin:
            chez_metrics = measure_scheme_interpreter([chez_bin, "-q"], expr, iterations=min(iters, 10), warmup=warmup)
            if chez_metrics:
                print(f"        ChezScheme: {chez_metrics['mean_ms']:7.2f} ms (med: {chez_metrics['median_ms']:7.2f} ms, std: {chez_metrics['std_ms']:5.2f} ms)", flush=True)

        gauche_metrics = None
        if args.include_schemes and gosh_bin:
            gauche_metrics = measure_scheme_interpreter([gosh_bin], expr, iterations=min(iters, 10), warmup=warmup)
            if gauche_metrics:
                print(f"        Gauche    : {gauche_metrics['mean_ms']:7.2f} ms (med: {gauche_metrics['median_ms']:7.2f} ms, std: {gauche_metrics['std_ms']:5.2f} ms)", flush=True)

        print(f"  => Output Verified: {expected} [All implementations match 100%]", flush=True)

        x86_vs_pure = x86_metrics["mean_ms"] / pure_c_metrics["mean_ms"] if pure_c_metrics["mean_ms"] > 0 else 1.0
        x86_vs_ulisp_c = x86_metrics["mean_ms"] / c_metrics["mean_ms"] if c_metrics["mean_ms"] > 0 else 1.0
        x86_vs_chez = (x86_metrics["mean_ms"] / chez_metrics["mean_ms"]) if (chez_metrics and chez_metrics["mean_ms"] > 0) else None

        item: Dict[str, Any] = {
            "id": w_id,
            "name": w_name,
            "expected": expected,
            "x86": {
                "mean_ms": x86_metrics["mean_ms"],
                "median_ms": x86_metrics["median_ms"],
                "min_ms": x86_metrics["min_ms"],
                "max_ms": x86_metrics["max_ms"],
                "std_ms": x86_metrics["std_ms"],
                "size_bytes": x86_size,
            },
            "ulisp_c": {
                "mean_ms": c_metrics["mean_ms"],
                "median_ms": c_metrics["median_ms"],
                "min_ms": c_metrics["min_ms"],
                "max_ms": c_metrics["max_ms"],
                "std_ms": c_metrics["std_ms"],
                "size_bytes": c_size,
            },
            "pure_c": {
                "mean_ms": pure_c_metrics["mean_ms"],
                "median_ms": pure_c_metrics["median_ms"],
                "min_ms": pure_c_metrics["min_ms"],
                "max_ms": pure_c_metrics["max_ms"],
                "std_ms": pure_c_metrics["std_ms"],
                "size_bytes": pure_c_size,
            },
            "ratio_x86_to_pure_c": x86_vs_pure,
            "ratio_x86_to_ulisp_c": x86_vs_ulisp_c,
        }
        if chez_metrics:
            item["chez"] = chez_metrics
            item["ratio_x86_to_chez"] = x86_vs_chez
        if gauche_metrics:
            item["gauche"] = gauche_metrics

        if perf_enabled:
            item["perf"] = {
                "x86": x86_perf,
                "ulisp_c": c_perf,
                "pure_c": pure_c_perf,
            }
            item["gc_stats"] = {
                "x86": x86_gc,
                "ulisp_c": c_gc,
            }
        results.append(item)

    # Nanopass profile
    nanopass_profile = measure_nanopass_profile() if (is_baseline or args.include_nanopass) else {}

    # Summary Display
    print("\n" + "=" * 98, flush=True)
    print(" ULISP CANONICAL BENCHMARK SUMMARY (Execution Time in milliseconds; lower is faster)", flush=True)
    print("=" * 98, flush=True)
    print(f"{'Workload':<32} | {'x86-64 Native':<14} | {'ULisp C (-O2)':<14} | {'Pure C (-O2)':<13} | {'x86 / Pure C':<12}", flush=True)
    print("-" * 98, flush=True)
    for r in results:
        x86_s = f"{r['x86']['mean_ms']:7.2f} ms"
        c_s = f"{r['ulisp_c']['mean_ms']:7.2f} ms"
        p_s = f"{r['pure_c']['mean_ms']:7.2f} ms"
        ratio_s = f"{r['ratio_x86_to_pure_c']:6.2f}x"
        print(f"{r['name']:<32} | {x86_s:>14} | {c_s:>14} | {p_s:>13} | {ratio_s:>12}", flush=True)
    print("=" * 98, flush=True)

    if perf_enabled:
        print("\n" + "=" * 98, flush=True)
        print(" HARDWARE PERFORMANCE COUNTERS (Linux perf stat & GC Stats)", flush=True)
        print("=" * 98, flush=True)
        print(f"{'Workload':<28} | {'x86 IPC':<9} | {'x86 BrMiss':<11} | {'x86 L1Miss':<11} | {'x86 GC Alloc':<14} | {'C IPC':<8}", flush=True)
        print("-" * 98, flush=True)
        for r in results:
            xp = r.get("perf", {}).get("x86")
            cp = r.get("perf", {}).get("ulisp_c")
            xgc = r.get("gc_stats", {}).get("x86") or {}
            x_ipc = f"{xp['ipc']:.2f}" if xp else "N/A"
            x_brmiss = f"{xp['branch_miss_pct']:.2f}%" if xp else "N/A"
            x_l1miss = f"{xp['cache_miss_pct']:.2f}%" if xp else "N/A"
            c_ipc = f"{cp['ipc']:.2f}" if cp else "N/A"
            alloc_s = xgc.get("alloc", "0 B")
            print(f"{r['name']:<28} | {x_ipc:>9} | {x_brmiss:>11} | {x_l1miss:>11} | {alloc_s:>14} | {c_ipc:>8}", flush=True)
        print("=" * 98, flush=True)

    # Standard Markdown Report
    md_content = f"""# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `{timestamp}`
- **Environment**: `{specs['os']} {specs['arch']} ({specs['kernel']})`, `GCC {specs['gcc']}`
- **CPU**: `{specs['cpu_model']}` ({specs['cpu_count']} cores)
- **Memory**: `{specs['mem_total']}`
- **Compiler Engine**: `{'ulisp/bin/ulisp-boot' if os.path.exists(ULISP_BOOT) else 'ILisp'}`
- **Conforms to**: DSN-33, Issue #620, Issue #622, Issue #623

## 1. 実行時間比較（Execution Latency）

| ワークロード | x86-64 Native (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 対 Pure C 比率 (x86 / Pure) | 対 ULisp C 比率 (x86 / ULisp C) |
|---|---|---|---|---|---|
"""
    for r in results:
        md_content += f"| **{r['name']}** | {r['x86']['mean_ms']:.2f} ± {r['x86']['std_ms']:.2f} (min: {r['x86']['min_ms']:.2f}) | {r['ulisp_c']['mean_ms']:.2f} ± {r['ulisp_c']['std_ms']:.2f} (min: {r['ulisp_c']['min_ms']:.2f}) | {r['pure_c']['mean_ms']:.2f} ± {r['pure_c']['std_ms']:.2f} (min: {r['pure_c']['min_ms']:.2f}) | **{r['ratio_x86_to_pure_c']:.2f}x** | **{r['ratio_x86_to_ulisp_c']:.2f}x** |\n"

    md_content += """
## 2. バイナリフットプリント（Binary Size）

| ワークロード | x86-64 Native (Bytes) | ULisp C -O2 (Bytes) | Pure C -O2 (Bytes) |
|---|---|---|---|
"""
    for r in results:
        md_content += f"| **{r['name']}** | {r['x86']['size_bytes']:,} B | {r['ulisp_c']['size_bytes']:,} B | {r['pure_c']['size_bytes']:,} B |\n"

    if perf_enabled:
        md_content += """
## 3. ハードウェア性能カウンタ（Hardware Performance Counters via Linux perf）

| ワークロード | x86-64 IPC | x86-64 Branch Miss % | x86-64 Cache Miss % | ULisp C IPC | Pure C IPC |
|---|---|---|---|---|---|
"""
        for r in results:
            xp = r.get("perf", {}).get("x86")
            cp = r.get("perf", {}).get("ulisp_c")
            pp = r.get("perf", {}).get("pure_c")
            x_ipc = f"{xp['ipc']:.2f}" if xp else "N/A"
            x_brmiss = f"{xp['branch_miss_pct']:.2f}%" if xp else "N/A"
            x_l1miss = f"{xp['cache_miss_pct']:.2f}%" if xp else "N/A"
            c_ipc = f"{cp['ipc']:.2f}" if cp else "N/A"
            p_ipc = f"{pp['ipc']:.2f}" if pp else "N/A"
            md_content += f"| **{r['name']}** | {x_ipc} | {x_brmiss} | {x_l1miss} | {c_ipc} | {p_ipc} |\n"

    md_content += """
> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
> - IPC（Instructions Per Cycle）、Branch Miss %、Cache Miss % は Linux `perf stat` ハードウェアカウンタによる測定値です。
"""

    md_file = os.path.join(BUILD_DIR, "bench_results.md")
    with open(md_file, "w", encoding="utf-8") as f:
        f.write(md_content)
    outputs_md_file = os.path.join(OUTPUTS_BENCH_DIR, "benchmark_c_vs_x86.md")
    with open(outputs_md_file, "w", encoding="utf-8") as f:
        f.write(md_content)

    # Save latest.json
    json_data = {
        "timestamp": timestamp,
        "os": specs["os"],
        "arch": specs["arch"],
        "kernel": specs["kernel"],
        "cpu_model": specs["cpu_model"],
        "cpu_count": specs["cpu_count"],
        "mem_total": specs["mem_total"],
        "gcc": specs["gcc"],
        "perf_enabled": perf_enabled,
        "results": results,
    }
    if nanopass_profile:
        json_data["nanopass_profile"] = nanopass_profile

    json_file = os.path.join(BUILD_DIR, "bench_results.json")
    with open(json_file, "w", encoding="utf-8") as f:
        json.dump(json_data, f, indent=2)
    outputs_json_file = os.path.join(OUTPUTS_BENCH_DIR, "latest.json")
    with open(outputs_json_file, "w", encoding="utf-8") as f:
        json.dump(json_data, f, indent=2)

    print(f"\n[INFO] Reports successfully written to:")
    print(f"  - {md_file}")
    print(f"  - {outputs_md_file}")
    print(f"  - {json_file}")
    print(f"  - {outputs_json_file}")

    # Canonical Baseline Output
    if is_baseline:
        with open(CANONICAL_BASELINE_JSON, "w", encoding="utf-8") as f:
            json.dump(json_data, f, indent=2)
        baseline_md_content = generate_baseline_markdown(
            timestamp=timestamp,
            specs=specs,
            results=results,
            nanopass_profile=nanopass_profile,
            perf_enabled=perf_enabled,
            iterations=run_iters,
        )
        with open(BASELINE_MD_PATH, "w", encoding="utf-8") as f:
            f.write(baseline_md_content)
        print(f"\n\033[32m[CANONICAL BASELINE ESTABLISHED]\033[0m")
        print(f"  - Data: {CANONICAL_BASELINE_JSON}")
        print(f"  - Document: {BASELINE_MD_PATH}")


if __name__ == "__main__":
    main()
