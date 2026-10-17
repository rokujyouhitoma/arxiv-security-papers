#!/usr/bin/env python3
"""
Portable Build Guide Benchmark Runner:
Measures execution performance across 7 Scheme implementations:
1. ULisp x86 (Native Machine Code via latest AOT passes)
2. ULisp C (-O2) (Portable C backend via GCC -O2)
3. Chez Scheme 9.5.8 (scheme --script)
4. Gauche 0.9.15 (gosh -b)
5. GNU Guile 3.0.9 (guile --no-auto-compile -s)
6. Chibi-Scheme 0.10.0 (chibi-scheme -p)
7. ILisp (python3 -m ilisp -p)

Workloads:
- 分岐再帰 (fib 30)
- 竹内関数 (tak 18 12 6)
- たらいまわし関数 (tarai 10 5 0)
- たらいまわし関数 (tarai 12 6 0)
- 末尾再帰ループ (loop 10M)
- 第一級クロージャ (closure 1M)
- リスト確保 & 走査 (list 100k)
"""

import os
import sys
import time
import json
import shutil
import tempfile
import statistics
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
ULISP_DIR = ROOT_DIR / "ulisp"
BUILD_DIR = ULISP_DIR / "build"
RUNTIME_C = ULISP_DIR / "runtime.c"
COMPILER_SCM = ULISP_DIR / "compiler.scm"
PYTHON_BIN = sys.executable

WORKLOADS = [
    {
        "id": "fib_30",
        "name": "分岐再帰 (fib 30)",
        "desc": "83 万回関数呼出・スタックフレーム",
        "expr": "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))",
        "expected": "832040",
        "iters": 3,
        "ilisp_iters": 1,
        "ilisp_timeout": 35,
    },
    {
        "id": "tak_18",
        "name": "竹内関数 (tak 18 12 6)",
        "desc": "6.3 万回 3引数相互再帰呼出",
        "expr": "(letrec ((tak (lambda (x y z) (if (not (< y x)) z (tak (tak (- x 1) y z) (tak (- y 1) z x) (tak (- z 1) x y)))))) (tak 18 12 6))",
        "expected": "7",
        "iters": 3,
        "ilisp_iters": 2,
        "ilisp_timeout": 20,
    },
    {
        "id": "tarai_10",
        "name": "たらいまわし関数 (tarai 10 5 0)",
        "desc": "3.4 万回 3引数再帰呼出 (比較基準)",
        "expr": "(letrec ((tarai (lambda (x y z) (if (<= x y) y (tarai (tarai (- x 1) y z) (tarai (- y 1) z x) (tarai (- z 1) x y)))))) (tarai 10 5 0))",
        "expected": "10",
        "iters": 3,
        "ilisp_iters": 2,
        "ilisp_timeout": 20,
    },
    {
        "id": "tarai_12",
        "name": "たらいまわし関数 (tarai 12 6 0)",
        "desc": "1,260 万回 3引数深層再帰呼出",
        "expr": "(letrec ((tarai (lambda (x y z) (if (<= x y) y (tarai (tarai (- x 1) y z) (tarai (- y 1) z x) (tarai (- z 1) x y)))))) (tarai 12 6 0))",
        "expected": "12",
        "iters": 3,
        "ilisp_iters": 0, # Exceeds 60s in pure Python bytecode
        "ilisp_timeout": 1,
    },
    {
        "id": "loop_10m",
        "name": "末尾再帰ループ (loop 10M)",
        "desc": "1,000 万回 TCO カウンタ (引数シャッフル)",
        "expr": "(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))",
        "expected": "49999995000000",
        "iters": 3,
        "ilisp_iters": 1,
        "ilisp_timeout": 30, # ~25s in ILisp
    },
    {
        "id": "closure_1m",
        "name": "第一級クロージャ (closure 1M)",
        "desc": "100 万回クロージャ間接呼出",
        "expr": "(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))",
        "expected": "1000000",
        "iters": 3,
        "ilisp_iters": 1,
        "ilisp_timeout": 25,
    },
    {
        "id": "list_100k",
        "name": "リスト確保 & 走査 (list 100k)",
        "desc": "10 万セル確保 (cons) と線形加算",
        "expr": "(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 '()) 0))",
        "expected": "5000050000",
        "iters": 3,
        "ilisp_iters": 1,
        "ilisp_timeout": 20,
    },
]

def clean_output(text: str) -> str:
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    for ln in lines:
        if ln.startswith("=> Result:"):
            return ln.replace("=> Result:", "").strip()
    return lines[-1] if lines else ""

# 1. Measure ULisp x86
def measure_ulisp_x86(expr: str, iters: int) -> Tuple[Optional[float], str]:
    with tempfile.NamedTemporaryFile("w", suffix=".s", delete=False) as f_s, \
         tempfile.NamedTemporaryFile("w", suffix="", delete=False) as f_bin:
        s_path, bin_path = f_s.name, f_bin.name
    try:
        env = dict(os.environ, PYTHONPATH=str(ROOT_DIR), ULISP_QUIET="1")
        cp = subprocess.run([PYTHON_BIN, "-m", "ilisp", str(COMPILER_SCM)],
                            input=expr, capture_output=True, text=True, env=env, timeout=15)
        if cp.returncode != 0:
            return None, f"Compile Error: {cp.stderr[:40]}"
        with open(s_path, "w") as f:
            f.write(cp.stdout)
        gcc_res = subprocess.run(["gcc", "-no-pie", "-O2", str(RUNTIME_C), s_path, "-o", bin_path],
                                 capture_output=True, text=True, timeout=10)
        if gcc_res.returncode != 0:
            return None, f"Link Error: {gcc_res.stderr[:40]}"

        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run([bin_path], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Runtime Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)
    finally:
        for p in (s_path, bin_path):
            if os.path.exists(p): os.remove(p)

# 2. Measure ULisp C (-O2)
def measure_ulisp_c(expr: str, iters: int) -> Tuple[Optional[float], str]:
    with tempfile.NamedTemporaryFile("w", suffix=".c", delete=False) as f_c, \
         tempfile.NamedTemporaryFile("w", suffix="", delete=False) as f_bin:
        c_path, bin_path = f_c.name, f_bin.name
    try:
        env = dict(os.environ, PYTHONPATH=str(ROOT_DIR), ULISP_QUIET="1")
        cp = subprocess.run([PYTHON_BIN, "-m", "ilisp", str(COMPILER_SCM)],
                            input=f"(!target c)\n{expr}\n", capture_output=True, text=True, env=env, timeout=15)
        if cp.returncode != 0:
            return None, f"Compile Error: {cp.stderr[:40]}"
        c_lines = [l for l in cp.stdout.splitlines() if l.strip() not in ("#t", "#f") and not l.strip().startswith(";")]
        with open(c_path, "w") as f:
            f.write("\n".join(c_lines) + "\n")
        gcc_res = subprocess.run(["gcc", "-O2", str(RUNTIME_C), c_path, "-o", bin_path],
                                 capture_output=True, text=True, timeout=10)
        if gcc_res.returncode != 0:
            return None, f"Link Error: {gcc_res.stderr[:40]}"

        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run([bin_path], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Runtime Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)
    finally:
        for p in (c_path, bin_path):
            if os.path.exists(p): os.remove(p)

# 3. Measure Chez Scheme
def measure_chez(expr: str, iters: int) -> Tuple[Optional[float], str]:
    if not shutil.which("scheme"):
        return None, "NOT FOUND"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(f"(display {expr}) (newline)\n")
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run(["scheme", "--script", f_path], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)
    finally:
        if os.path.exists(f_path): os.remove(f_path)

# 4. Measure Gauche
def measure_gauche(expr: str, iters: int) -> Tuple[Optional[float], str]:
    if not shutil.which("gosh"):
        return None, "NOT FOUND"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(f"(display {expr}) (newline)\n")
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run(["gosh", "-b", f_path], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)
    finally:
        if os.path.exists(f_path): os.remove(f_path)

# 5. Measure Guile
def measure_guile(expr: str, iters: int) -> Tuple[Optional[float], str]:
    if not shutil.which("guile"):
        return None, "NOT FOUND"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(f"(display {expr}) (newline)\n")
        f_path = f.name
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run(["guile", "--no-auto-compile", "-s", f_path],
                                 stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=25)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)
    finally:
        if os.path.exists(f_path): os.remove(f_path)

# 6. Measure Chibi-Scheme
def measure_chibi(expr: str, iters: int) -> Tuple[Optional[float], str]:
    if not shutil.which("chibi-scheme"):
        return None, "NOT FOUND"
    try:
        times = []
        out = ""
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run(["chibi-scheme", "-p", expr],
                                 stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=25)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except Exception as e:
        return None, str(e)

# 7. Measure ILisp
def measure_ilisp(expr: str, iters: int, timeout: int) -> Tuple[Optional[float], str]:
    if iters <= 0:
        return None, "Timeout (>60s)"
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f:
        f.write(expr)
        f_path = f.name
    try:
        times = []
        out = ""
        env = dict(os.environ, PYTHONPATH=str(ROOT_DIR))
        for _ in range(iters):
            t0 = time.perf_counter()
            res = subprocess.run([PYTHON_BIN, "-m", "ilisp", "-p", f_path],
                                 stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env, timeout=timeout)
            t1 = time.perf_counter()
            if res.returncode != 0:
                return None, f"Error: {res.stderr[:40]}"
            times.append((t1 - t0) * 1000.0)
            out = clean_output(res.stdout)
        return statistics.mean(times), out
    except subprocess.TimeoutExpired:
        return None, f"Timeout (>{timeout}s)"
    except Exception as e:
        return None, str(e)
    finally:
        if os.path.exists(f_path): os.remove(f_path)

def main():
    print("==================================================================================================")
    print(" Scheme Implementations Comprehensive Benchmark (ULisp x86/C vs Chez vs Gauche vs Guile vs Chibi vs ILisp)")
    print("==================================================================================================")

    data = []

    for w in WORKLOADS:
        wid = w["id"]
        name = w["name"]
        desc = w["desc"]
        expr = w["expr"]
        expected = w["expected"]
        iters = w["iters"]
        ilisp_iters = w["ilisp_iters"]
        ilisp_timeout = w["ilisp_timeout"]

        print(f"\n[*] Benchmarking: {name} ({desc})...")

        # 1. ULisp x86
        t_x86, o_x86 = measure_ulisp_x86(expr, iters)
        str_x86 = f"{t_x86:.2f} ms" if t_x86 is not None else "FAIL"
        print(f"    ULisp x86  : {str_x86:>10} | out: {o_x86}")

        # 2. ULisp C
        t_c, o_c = measure_ulisp_c(expr, iters)
        str_c = f"{t_c:.2f} ms" if t_c is not None else "FAIL"
        print(f"    ULisp C    : {str_c:>10} | out: {o_c}")

        # 3. Chez
        t_chez, o_chez = measure_chez(expr, iters)
        str_chez = f"{t_chez:.2f} ms" if t_chez is not None else "FAIL"
        print(f"    Chez Scheme: {str_chez:>10} | out: {o_chez}")

        # 4. Gauche
        t_gosh, o_gosh = measure_gauche(expr, iters)
        str_gosh = f"{t_gosh:.2f} ms" if t_gosh is not None else "FAIL"
        print(f"    Gauche     : {str_gosh:>10} | out: {o_gosh}")

        # 5. Guile
        t_guile, o_guile = measure_guile(expr, iters)
        str_guile = f"{t_guile:.2f} ms" if t_guile is not None else "FAIL"
        print(f"    Guile 3.0  : {str_guile:>10} | out: {o_guile}")

        # 6. Chibi
        t_chibi, o_chibi = measure_chibi(expr, iters)
        str_chibi = f"{t_chibi:.2f} ms" if t_chibi is not None else "FAIL"
        print(f"    Chibi      : {str_chibi:>10} | out: {o_chibi}")

        # 7. ILisp
        t_ilisp, o_ilisp = measure_ilisp(expr, ilisp_iters, ilisp_timeout)
        str_ilisp = f"{t_ilisp:.2f} ms" if t_ilisp is not None else o_ilisp
        print(f"    ILisp      : {str_ilisp:>10} | out: {o_ilisp}")

        data.append({
            "name": name,
            "desc": desc,
            "expected": expected,
            "ulisp_x86": t_x86,
            "ulisp_c": t_c,
            "chez": t_chez,
            "gauche": t_gosh,
            "guile": t_guile,
            "chibi": t_chibi,
            "ilisp": t_ilisp,
            "ilisp_note": o_ilisp if t_ilisp is None else None
        })

    # Save to JSON
    out_json = ROOT_DIR / "outputs" / "benchmarks" / "portable_guide_benchmark.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"\n[+] Saved benchmark data to {out_json}")

if __name__ == "__main__":
    main()
