#!/usr/bin/env python3
"""
ULisp Canonical Benchmark Suite:
x86-64 Native Bare-Metal (Freestanding) vs ULisp Portable C vs Pure C Baseline (-O2)
Measures execution latency (mean, min, max, stdev) and binary size across 6 representative workloads.
Conforms to DSN-33 and Issue #620.
"""

import datetime
import json
import os
import platform
import statistics
import subprocess
import sys
import time

ULISP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT_DIR = os.path.abspath(os.path.join(ULISP_DIR, ".."))
BUILD_DIR = os.path.join(ULISP_DIR, "build", "bench_c_x86")
OUTPUTS_BENCH_DIR = os.path.join(ROOT_DIR, "outputs", "benchmarks")
os.makedirs(BUILD_DIR, exist_ok=True)
os.makedirs(OUTPUTS_BENCH_DIR, exist_ok=True)

PYTHON_BIN = sys.executable
COMPILER_SCM = os.path.join(ULISP_DIR, "compiler.scm")
ULISP_BOOT = os.path.join(ULISP_DIR, "bin", "ulisp-boot")

# 6 Canonical Workloads conforming to Issue #620
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

def run_cmd(cmd, input_text=None, cwd=ULISP_DIR):
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

def compile_scheme_to_file(in_code, out_path):
    """Compiles Scheme code to output file (.s or .c) using ulisp-boot or ilisp fallback."""
    tmp_scm = os.path.join(BUILD_DIR, "tmp_bench_in.scm")
    with open(tmp_scm, "w") as f:
        f.write(in_code)

    if os.path.exists(ULISP_BOOT) and os.access(ULISP_BOOT, os.X_OK):
        with open(out_path, "w") as out_f:
            env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
            res = subprocess.run([ULISP_BOOT, tmp_scm], stdout=out_f, stderr=subprocess.PIPE, text=True, env=env)
            if res.returncode != 0:
                raise RuntimeError(f"ulisp-boot failed: {res.stderr}")
    else:
        out_str = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=in_code)
        with open(out_path, "w") as out_f:
            out_f.write(out_str)

def compile_x86(workload_id, expr):
    s_path = os.path.join(BUILD_DIR, f"{workload_id}.s")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_x86")
    compile_scheme_to_file(expr, s_path)
    # Freestanding x86-64 binary linking (zero libc)
    run_cmd(["gcc", "-nostdlib", "-static", s_path, "-o", bin_path])
    return bin_path

def compile_ulisp_c(workload_id, expr):
    c_path = os.path.join(BUILD_DIR, f"{workload_id}_ulisp.c")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_ulisp_c")
    c_input = f"(!target c)\n{expr}"
    compile_scheme_to_file(c_input, c_path)
    # Standalone C99 compilation (Pass 160 includes its own runtime)
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-label", "-O2", c_path, "-o", bin_path])
    return bin_path

def compile_pure_c(workload_id, c_source):
    c_path = os.path.join(BUILD_DIR, f"{workload_id}_pure.c")
    bin_path = os.path.join(BUILD_DIR, f"{workload_id}_pure_c")
    with open(c_path, "w") as f:
        f.write(c_source)
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-O2", c_path, "-o", bin_path])
    return bin_path

def verify_output(bin_path):
    """Executes the binary without ULISP_QUIET to obtain and verify stdout."""
    env = os.environ.copy()
    env.pop("ULISP_QUIET", None)
    p = subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)
    return p.stdout.strip()

def measure_execution(bin_path, iterations, warmup=3):
    """Measures runtime latency with ULISP_QUIET=1 to eliminate I/O overhead."""
    env = dict(os.environ, ULISP_QUIET="1")
    # Warmup runs to prime CPU caches & branch predictors
    for _ in range(warmup):
        subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)

    times = []
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        subprocess.run([bin_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, text=True, env=env)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0) # convert to milliseconds

    mean_ms = statistics.mean(times)
    min_ms = min(times)
    max_ms = max(times)
    std_ms = statistics.stdev(times) if len(times) > 1 else 0.0
    return {
        "mean_ms": mean_ms,
        "min_ms": min_ms,
        "max_ms": max_ms,
        "std_ms": std_ms,
    }

def main():
    gcc_ver = subprocess.getoutput("gcc -dumpversion").strip()
    cpu_arch = platform.machine()
    os_name = platform.system()
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()

    print("=" * 88, flush=True)
    print(" ULisp Canonical Performance Benchmark: x86-64 Freestanding vs ULisp C vs Pure C", flush=True)
    print(f" Environment: {os_name} {cpu_arch}, GCC {gcc_ver}, Engine: {'ulisp-boot' if os.path.exists(ULISP_BOOT) else 'ILisp'}", flush=True)
    print("=" * 88, flush=True)

    results = []

    for idx, w in enumerate(WORKLOADS, 1):
        w_id = w["id"]
        w_name = w["name"]
        expr = w["scheme_expr"]
        pure_c_src = w["pure_c"]
        expected = w["expected"]
        iters = w["iters"]
        warmup = w["warmup"]

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
        print(f"        Execution: {x86_metrics['mean_ms']:7.2f} ms (min: {x86_metrics['min_ms']:7.2f} ms, std: {x86_metrics['std_ms']:5.2f} ms) | Size: {x86_size:6d} B", flush=True)

        # 2. ULisp C Backend (-O2)
        print("  [2/3] Compiling ULisp C backend (-O2)...", end="", flush=True)
        t_c1 = time.time()
        c_bin = compile_ulisp_c(w_id, expr)
        print(f" done ({time.time() - t_c1:.2f}s)", flush=True)
        c_size = os.path.getsize(c_bin)
        c_out = verify_output(c_bin)
        assert c_out == expected, f"Output mismatch for ULisp C in {w_name}: expected '{expected}', got '{c_out}'"
        c_metrics = measure_execution(c_bin, iters, warmup)
        print(f"        Execution: {c_metrics['mean_ms']:7.2f} ms (min: {c_metrics['min_ms']:7.2f} ms, std: {c_metrics['std_ms']:5.2f} ms) | Size: {c_size:6d} B", flush=True)

        # 3. Pure C Baseline (-O2)
        print("  [3/3] Compiling Pure C baseline (-O2)...", end="", flush=True)
        t_c2 = time.time()
        pure_c_bin = compile_pure_c(w_id, pure_c_src)
        print(f" done ({time.time() - t_c2:.2f}s)", flush=True)
        pure_c_size = os.path.getsize(pure_c_bin)
        pure_c_out = verify_output(pure_c_bin)
        assert pure_c_out == expected, f"Output mismatch for Pure C in {w_name}: expected '{expected}', got '{pure_c_out}'"
        pure_c_metrics = measure_execution(pure_c_bin, iters, warmup)
        print(f"        Execution: {pure_c_metrics['mean_ms']:7.2f} ms (min: {pure_c_metrics['min_ms']:7.2f} ms, std: {pure_c_metrics['std_ms']:5.2f} ms) | Size: {pure_c_size:6d} B", flush=True)

        print(f"  => Output Verified: {expected} [All 3 implementations match 100%]", flush=True)

        # Relative speedups
        x86_vs_pure = x86_metrics["mean_ms"] / pure_c_metrics["mean_ms"] if pure_c_metrics["mean_ms"] > 0 else 1.0
        x86_vs_ulisp_c = x86_metrics["mean_ms"] / c_metrics["mean_ms"] if c_metrics["mean_ms"] > 0 else 1.0

        results.append({
            "id": w_id,
            "name": w_name,
            "expected": expected,
            "x86": {
                "mean_ms": x86_metrics["mean_ms"],
                "min_ms": x86_metrics["min_ms"],
                "max_ms": x86_metrics["max_ms"],
                "std_ms": x86_metrics["std_ms"],
                "size_bytes": x86_size,
            },
            "ulisp_c": {
                "mean_ms": c_metrics["mean_ms"],
                "min_ms": c_metrics["min_ms"],
                "max_ms": c_metrics["max_ms"],
                "std_ms": c_metrics["std_ms"],
                "size_bytes": c_size,
            },
            "pure_c": {
                "mean_ms": pure_c_metrics["mean_ms"],
                "min_ms": pure_c_metrics["min_ms"],
                "max_ms": pure_c_metrics["max_ms"],
                "std_ms": pure_c_metrics["std_ms"],
                "size_bytes": pure_c_size,
            },
            "ratio_x86_to_pure_c": x86_vs_pure,
            "ratio_x86_to_ulisp_c": x86_vs_ulisp_c,
        })

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

    # Generate Markdown Report
    md_content = f"""# ULisp Canonical Benchmark Report: x86-64 vs ULisp C vs Pure C

- **Timestamp**: `{timestamp}`
- **Environment**: `{os_name} {cpu_arch}`, `GCC {gcc_ver}`
- **Compiler Engine**: `{'ulisp/bin/ulisp-boot' if os.path.exists(ULISP_BOOT) else 'ILisp'}`
- **Conforms to**: DSN-33, Issue #620

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

    md_content += """
> **注記**:
> - x86-64 Native は `gcc -nostdlib -static` でリンクされた libc 依存ゼロの Freestanding バイナリです。
> - ULisp C は Pass 160 で出力された自己完結型 C99 ソースを `gcc -O2` でビルドしたバイナリです。
> - Pure C は同一アルゴリズムの手書き最適化 C99 コードを `gcc -O2` でビルドした理論上限ベースラインです。
"""

    md_file = os.path.join(BUILD_DIR, "bench_results.md")
    with open(md_file, "w") as f:
        f.write(md_content)
    outputs_md_file = os.path.join(OUTPUTS_BENCH_DIR, "benchmark_c_vs_x86.md")
    with open(outputs_md_file, "w") as f:
        f.write(md_content)

    # Generate JSON Report
    json_data = {
        "timestamp": timestamp,
        "os": os_name,
        "arch": cpu_arch,
        "gcc": gcc_ver,
        "results": results,
    }
    json_file = os.path.join(BUILD_DIR, "bench_results.json")
    with open(json_file, "w") as f:
        json.dump(json_data, f, indent=2)
    outputs_json_file = os.path.join(OUTPUTS_BENCH_DIR, "latest.json")
    with open(outputs_json_file, "w") as f:
        json.dump(json_data, f, indent=2)

    print(f"\n[INFO] Reports successfully written to:")
    print(f"  - {md_file}")
    print(f"  - {outputs_md_file}")
    print(f"  - {json_file}")
    print(f"  - {outputs_json_file}")

if __name__ == "__main__":
    main()
