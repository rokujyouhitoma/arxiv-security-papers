#!/usr/bin/env python3
"""
ULisp Benchmark: x86-64 Native Bare-Metal vs Portable C Backend (-O2)
Measures execution time and binary size across representative workloads.
"""

import os
import subprocess
import time
import sys
import statistics

ULISP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT_DIR = os.path.abspath(os.path.join(ULISP_DIR, ".."))
BUILD_DIR = os.path.join(ULISP_DIR, "build", "bench_c_x86")
os.makedirs(BUILD_DIR, exist_ok=True)

PYTHON_BIN = sys.executable
COMPILER_SCM = os.path.join(ULISP_DIR, "compiler.scm")
RUNTIME_C = os.path.join(ULISP_DIR, "runtime.c")

# Benchmarks: (Name, Scheme Expr, Iterations)
BENCHMARKS = [
    (
        "Fibonacci (fib 30)",
        "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))",
        5,
    ),
    (
        "Tail-Recursive Loop (10M)",
        "(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))",
        10,
    ),
    (
        "Ackermann (ack 3 7)",
        "(letrec ((ack (lambda (m n) (if (= m 0) (+ n 1) (if (= n 0) (ack (- m 1) 1) (ack (- m 1) (ack m (- n 1)))))))) (ack 3 7))",
        5,
    ),
    (
        "Higher-Order Closure (1M)",
        "(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))",
        10,
    ),
    (
        "List Alloc & Traverse (100k)",
        "(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 ()) 0))",
        10,
    ),
]

def run_cmd(cmd, input_text=None):
    env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1")
    p = subprocess.run(cmd, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if p.returncode != 0:
        raise RuntimeError(f"Command failed ({cmd}):\n{p.stderr}")
    return p.stdout

def compile_x86(name, expr):
    s_path = os.path.join(BUILD_DIR, f"{name}.s")
    bin_path = os.path.join(BUILD_DIR, f"{name}_x86")
    
    # Compile S-expression to x86-64 assembly using ilisp compiler.scm
    s_code = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=expr)
    with open(s_path, "w") as f:
        f.write(s_code)
    
    # Link freestanding x86 binary
    run_cmd(["gcc", "-nostdlib", "-static", s_path, "-o", bin_path])
    return bin_path

def compile_c(name, expr):
    c_path = os.path.join(BUILD_DIR, f"{name}.c")
    bin_path = os.path.join(BUILD_DIR, f"{name}_c")
    
    c_input = f"(!target c)\n{expr}"
    c_code = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=c_input)
    with open(c_path, "w") as f:
        f.write(c_code)
    
    # Compile with GCC -O2
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-O2", RUNTIME_C, c_path, "-o", bin_path])
    return bin_path

def measure_execution(bin_path, iterations):
    times = []
    output = None
    for _ in range(iterations):
        t0 = time.perf_counter_ns()
        p = subprocess.run([bin_path], stdout=subprocess.PIPE, check=True, text=True)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0)
        output = p.stdout.strip()
    return statistics.mean(times), min(times), statistics.stdev(times) if len(times) > 1 else 0.0, output

def main():
    print("=" * 80, flush=True)
    print(" ULisp Benchmark: x86-64 Native Bare-Metal vs Portable C Backend (-O2)", flush=True)
    print(" Environment: Linux x86_64, GCC 13.x", flush=True)
    print("=" * 80, flush=True)
    
    results = []
    
    for idx, (bench_name, expr, iters) in enumerate(BENCHMARKS, 1):
        safe_name = f"bench_{idx}"
        print(f"\n[{idx}/{len(BENCHMARKS)}] Benchmarking: {bench_name} (iters={iters})...", flush=True)
        
        print("  Compiling x86-64 native...", end="", flush=True)
        t_c0 = time.time()
        x86_bin = compile_x86(safe_name, expr)
        print(f" done ({time.time() - t_c0:.1f}s)", flush=True)
        x86_size = os.path.getsize(x86_bin)
        
        print("  Measuring x86-64...", end="", flush=True)
        x86_mean, x86_min, x86_std, x86_out = measure_execution(x86_bin, iters)
        print(f" done: {x86_mean:7.2f} ms (min: {x86_min:7.2f} ms) | Size: {x86_size:6d} B | Output: {x86_out}", flush=True)
        
        print("  Compiling Portable C...", end="", flush=True)
        t_c1 = time.time()
        c_bin = compile_c(safe_name, expr)
        print(f" done ({time.time() - t_c1:.1f}s)", flush=True)
        c_size = os.path.getsize(c_bin)
        
        print("  Measuring C backend...", end="", flush=True)
        c_mean, c_min, c_std, c_out = measure_execution(c_bin, iters)
        print(f" done: {c_mean:7.2f} ms (min: {c_min:7.2f} ms) | Size: {c_size:6d} B | Output: {c_out}", flush=True)
        
        assert x86_out == c_out, f"Output mismatch: x86 '{x86_out}' vs C '{c_out}'"
        
        ratio = c_mean / x86_mean if x86_mean > 0 else 1.0
        better = "(C is FASTER)" if ratio < 1.0 else "(x86-64 is FASTER)"
        print(f"  => Ratio (C / x86): {ratio:.2f}x {better}", flush=True)
        
        results.append({
            "name": bench_name,
            "x86_mean": x86_mean,
            "x86_min": x86_min,
            "x86_size": x86_size,
            "c_mean": c_mean,
            "c_min": c_min,
            "c_size": c_size,
            "ratio": ratio,
            "output": x86_out
        })
    
    print("\n" + "=" * 80, flush=True)
    print(" FINAL PERFORMANCE BENCHMARK SUMMARY", flush=True)
    print("=" * 80, flush=True)
    print(f"{'Benchmark Workload':<30} | {'x86-64 (ms)':<12} | {'C Backend (ms)':<14} | {'Speed Ratio':<14} | {'x86 Size':<9} | {'C Size':<9}", flush=True)
    print("-" * 96, flush=True)
    for r in results:
        if r['ratio'] < 1.0:
            diff_pct = round((1.0 / r['ratio'] - 1.0) * 100)
            ratio_str = f"{r['ratio']:.2f}x (C +{diff_pct}%)"
        else:
            diff_pct = round((r['ratio'] - 1.0) * 100)
            ratio_str = f"{r['ratio']:.2f}x (x86 +{diff_pct}%)"
        print(f"{r['name']:<30} | {r['x86_mean']:>10.2f} ms | {r['c_mean']:>12.2f} ms | {ratio_str:<14} | {r['x86_size']:>7d} B | {r['c_size']:>7d} B", flush=True)
    print("=" * 80, flush=True)

if __name__ == "__main__":
    main()
