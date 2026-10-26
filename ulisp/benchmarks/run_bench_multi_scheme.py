#!/usr/bin/env python3
"""
ULisp Multi-Implementation Benchmark:
Compares ULisp (x86-64 Native & Portable C) against major Scheme implementations:
- Chez Scheme (chezscheme)
- GNU Guile 3.0 (guile)
- Chibi-Scheme (chibi-scheme)
- Gauche (gosh, if available)
"""

import os
import subprocess
import time
import sys
import shutil
import statistics
import tempfile

ULISP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT_DIR = os.path.abspath(os.path.join(ULISP_DIR, ".."))
BUILD_DIR = os.path.join(ULISP_DIR, "build", "bench_multi")
os.makedirs(BUILD_DIR, exist_ok=True)

PYTHON_BIN = sys.executable
COMPILER_SCM = os.path.join(ULISP_DIR, "compiler.scm")
ULISP_BOOT = os.path.join(ULISP_DIR, "bin", "ulisp-boot")

CHEZ_BIN = shutil.which("chezscheme") or shutil.which("scheme")
GUILE_BIN = shutil.which("guile")
CHIBI_BIN = shutil.which("chibi-scheme")
GOSH_BIN = shutil.which("gosh")

WORKLOADS = [
    {
        "id": "fib_30",
        "name": "Recursive Fibonacci (fib 30)",
        "iters": 3,
        "expr": "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))",
        "expected": "832040",
    },
    {
        "id": "loop_10m",
        "name": "Tail-Recursive Loop (10,000,000)",
        "iters": 5,
        "expr": "(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))",
        "expected": "49999995000000",
    },
    {
        "id": "closure_1m",
        "name": "Higher-Order Closure (1,000,000)",
        "iters": 5,
        "expr": "(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))",
        "expected": "1000000",
    },
    {
        "id": "list_100k",
        "name": "List Alloc & Traverse (100,000)",
        "iters": 5,
        "expr": "(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 '()) 0))",
        "expected": "5000050000",
    },
]

def run_cmd(cmd, input_text=None):
    env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1")
    p = subprocess.run(cmd, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if p.returncode != 0:
        raise RuntimeError(f"Command failed ({cmd}):\n{p.stderr}")
    return p.stdout

def compile_ulisp_x86(name, expr):
    s_path = os.path.join(BUILD_DIR, f"{name}.s")
    bin_path = os.path.join(BUILD_DIR, f"{name}_x86")
    if os.path.exists(ULISP_BOOT) and os.access(ULISP_BOOT, os.X_OK):
        tmp_in = os.path.join(BUILD_DIR, f"tmp_{name}.scm")
        with open(tmp_in, "w") as f:
            f.write(expr)
        with open(s_path, "w") as f:
            env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
            subprocess.run([ULISP_BOOT, tmp_in], stdout=f, check=True, env=env)
    else:
        s_code = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=expr)
        with open(s_path, "w") as f:
            f.write(s_code)
    run_cmd(["gcc", "-nostdlib", "-static", s_path, "-o", bin_path])
    return bin_path

def compile_ulisp_c(name, expr):
    c_path = os.path.join(BUILD_DIR, f"{name}.c")
    bin_path = os.path.join(BUILD_DIR, f"{name}_c")
    c_expr = f"(!target c)\n{expr}"
    if os.path.exists(ULISP_BOOT) and os.access(ULISP_BOOT, os.X_OK):
        tmp_in = os.path.join(BUILD_DIR, f"tmp_{name}_c.scm")
        with open(tmp_in, "w") as f:
            f.write(c_expr)
        with open(c_path, "w") as f:
            env = dict(os.environ, PYTHONPATH=ROOT_DIR, ULISP_QUIET="1", ULISP_GC_PROFILE="compiler")
            subprocess.run([ULISP_BOOT, tmp_in], stdout=f, check=True, env=env)
    else:
        c_code = run_cmd([PYTHON_BIN, "-m", "ilisp", COMPILER_SCM], input_text=c_expr)
        with open(c_path, "w") as f:
            f.write(c_code)
    run_cmd(["gcc", "-Wall", "-Wextra", "-Werror", "-Wno-unused-label", "-O2", c_path, "-o", bin_path])
    return bin_path

def measure_bin(bin_path, iters):
    times = []
    out = ""
    for _ in range(iters):
        t0 = time.perf_counter_ns()
        p = subprocess.run([bin_path], stdout=subprocess.PIPE, text=True, check=True)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0)
        out = p.stdout.strip()
    return statistics.mean(times), min(times), out

def measure_chez(expr, iters):
    if not CHEZ_BIN:
        return None, None, None
    script = f"(display {expr}) (newline)\n"
    with tempfile.NamedTemporaryFile("w", suffix=".ss", delete=False) as f:
        f.write(script)
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter_ns()
            p = subprocess.run([CHEZ_BIN, "--script", f_path], stdout=subprocess.PIPE, text=True, check=True)
            t1 = time.perf_counter_ns()
            times.append((t1 - t0) / 1_000_000.0)
            out = p.stdout.strip()
        return statistics.mean(times), min(times), out
    except Exception as e:
        return None, None, f"ERROR: {e}"
    finally:
        if os.path.exists(f_path):
            os.remove(f_path)

def measure_guile(expr, iters):
    if not GUILE_BIN:
        return None, None, None
    script = f"(display {expr}) (newline)\n"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(script)
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter_ns()
            p = subprocess.run([GUILE_BIN, "--no-auto-compile", "-s", f_path], stdout=subprocess.PIPE, text=True, check=True)
            t1 = time.perf_counter_ns()
            times.append((t1 - t0) / 1_000_000.0)
            out = p.stdout.strip()
        return statistics.mean(times), min(times), out
    except Exception as e:
        return None, None, f"ERROR: {e}"
    finally:
        if os.path.exists(f_path):
            os.remove(f_path)


def measure_chibi(expr, iters):
    if not CHIBI_BIN:
        return None, None, None
    times = []
    out = ""
    for _ in range(iters):
        t0 = time.perf_counter_ns()
        p = subprocess.run([CHIBI_BIN, "-p", expr], stdout=subprocess.PIPE, text=True, check=True)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0)
        out = p.stdout.strip()
    return statistics.mean(times), min(times), out

def measure_gauche(expr, iters):
    gosh = shutil.which("gosh")
    if not gosh:
        return None, None, None
    script = f"(display (begin {expr})) (newline)\n"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(script)
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter_ns()
            p = subprocess.run([gosh, f_path], stdout=subprocess.PIPE, text=True, check=True)
            t1 = time.perf_counter_ns()
            times.append((t1 - t0) / 1_000_000.0)
            out = p.stdout.strip()
        return statistics.mean(times), min(times), out
    finally:
        if os.path.exists(f_path):
            os.remove(f_path)

def main():
    print("=" * 95, flush=True)
    print(" ULisp Comprehensive Benchmark: ULisp (x86 & C) vs Chez Scheme vs Guile vs Chibi vs Gauche", flush=True)
    print(f" Environment: Linux x86_64, GCC {subprocess.getoutput('gcc -dumpversion')}", flush=True)
    print("=" * 95, flush=True)
    
    table_rows = []
    
    for w in WORKLOADS:
        w_id = w["id"]
        w_name = w["name"]
        iters = w["iters"]
        expr = w["expr"]
        expected = w["expected"]
        
        print(f"\n--- Workload: {w_name} (iters={iters}) ---", flush=True)
        
        # 1. ULisp x86
        x86_bin = compile_ulisp_x86(w_id, expr)
        m_x86, min_x86, out_x86 = measure_bin(x86_bin, iters)
        print(f"  [ULisp x86-64] : {m_x86:7.2f} ms (out: {out_x86})", flush=True)
        
        # 2. ULisp C (-O2)
        c_bin = compile_ulisp_c(w_id, expr)
        m_c, min_c, out_c = measure_bin(c_bin, iters)
        print(f"  [ULisp C -O2]  : {m_c:7.2f} ms (out: {out_c})", flush=True)
        
        # 3. Chez Scheme
        m_chez, min_chez, out_chez = measure_chez(expr, iters)
        chez_str = f"{m_chez:7.2f} ms" if m_chez is not None else "N/A"
        print(f"  [Chez Scheme]  : {chez_str} (out: {out_chez})", flush=True)
        
        # 4. Guile 3.0
        m_guile, min_guile, out_guile = measure_guile(expr, iters)
        guile_str = f"{m_guile:7.2f} ms" if m_guile is not None else "N/A"
        print(f"  [Guile 3.0]    : {guile_str} (out: {out_guile})", flush=True)
        
        # 5. Chibi-Scheme
        m_chibi, min_chibi, out_chibi = measure_chibi(expr, iters)
        chibi_str = f"{m_chibi:7.2f} ms" if m_chibi is not None else "N/A"
        print(f"  [Chibi-Scheme] : {chibi_str} (out: {out_chibi})", flush=True)
        
        # 6. Gauche
        m_gosh, min_gosh, out_gosh = measure_gauche(expr, iters)
        gosh_str = f"{m_gosh:7.2f} ms" if m_gosh is not None else "N/A"
        print(f"  [Gauche]       : {gosh_str} (out: {out_gosh})", flush=True)
        
        table_rows.append({
            "name": w_name,
            "x86": m_x86,
            "c": m_c,
            "chez": m_chez,
            "guile": m_guile,
            "chibi": m_chibi,
            "gosh": m_gosh
        })
    
    print("\n" + "=" * 105, flush=True)
    print(" COMPREHENSIVE PERFORMANCE SUMMARY TABLE (Execution Time in milliseconds, lower is faster)", flush=True)
    print("=" * 105, flush=True)
    headers = ["Workload", "ULisp x86", "ULisp C (-O2)", "Chez Scheme", "Guile 3.0", "Chibi-Scheme", "Gauche"]
    print(f"{headers[0]:<34} | {headers[1]:<10} | {headers[2]:<13} | {headers[3]:<11} | {headers[4]:<10} | {headers[5]:<12} | {headers[6]:<10}", flush=True)
    print("-" * 115, flush=True)
    for r in table_rows:
        x86_s = f"{r['x86']:.2f} ms"
        c_s = f"{r['c']:.2f} ms"
        chez_s = f"{r['chez']:.2f} ms" if r['chez'] is not None else "N/A"
        guile_s = f"{r['guile']:.2f} ms" if r['guile'] is not None else "N/A"
        chibi_s = f"{r['chibi']:.2f} ms" if r['chibi'] is not None else "N/A"
        gosh_s = f"{r['gosh']:.2f} ms" if r['gosh'] is not None else "N/A"
        print(f"{r['name']:<34} | {x86_s:>10} | {c_s:>13} | {chez_s:>11} | {guile_s:>10} | {chibi_s:>12} | {gosh_s:>10}", flush=True)
    print("=" * 105, flush=True)

if __name__ == "__main__":
    main()
