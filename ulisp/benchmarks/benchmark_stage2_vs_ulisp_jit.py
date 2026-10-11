#!/usr/bin/env python3
"""
Performance Evaluation & Comparison Suite:
  ulisp/build/scheme-stage2 vs ulisp/bin/ulisp-jit
Conforms to Issue #512, Issue #514 & DSN-33
"""

import os
import subprocess
import time
import statistics
import tempfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
STAGE2_BIN = ROOT_DIR / "ulisp" / "build" / "scheme-stage2"
ULISP_JIT_BIN = ROOT_DIR / "ulisp" / "bin" / "ulisp-jit"
RUNTIME_C = ROOT_DIR / "ulisp" / "runtime.c"

def get_binary_metrics(bin_path):
    stat = os.stat(bin_path)
    file_size_bytes = stat.st_size
    size_output = subprocess.check_output(["size", str(bin_path)], text=True).strip().splitlines()
    text, data, bss = 0, 0, 0
    if len(size_output) > 1:
        parts = size_output[1].split()
        text, data, bss = int(parts[0]), int(parts[1]), int(parts[2])
    return {
        "file_size": file_size_bytes,
        "text": text,
        "data": data,
        "bss": bss,
    }

def benchmark_aot_compile(compiler_bin, input_code, iterations=30, is_jit=False):
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_in, \
         tempfile.NamedTemporaryFile("w", suffix=".s", delete=False) as f_out:
        in_path = f_in.name
        out_path = f_out.name
        # If testing ulisp-jit in AOT mode, prepend (!compile)
        if is_jit:
            f_in.write("(!compile)\n" + input_code)
        else:
            f_in.write(input_code)
        f_in.flush()

    times = []
    cmd = [str(compiler_bin), in_path]
    for _ in range(iterations):
        t0 = time.perf_counter()
        with open(out_path, "w") as out_f:
            res = subprocess.run(cmd, stdout=out_f, stderr=subprocess.PIPE, text=True)
        t1 = time.perf_counter()
        if res.returncode != 0:
            raise RuntimeError(f"Compiler failed: {res.stderr}")
        times.append((t1 - t0) * 1000.0) # ms

    # Clean up
    os.remove(in_path)
    os.remove(out_path)
    return {
        "mean_ms": statistics.mean(times),
        "std_ms": statistics.stdev(times) if len(times) > 1 else 0.0,
        "min_ms": min(times),
        "max_ms": max(times),
    }

def benchmark_jit_execution(jit_bin, loop_code, iterations=30):
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_in:
        in_path = f_in.name
        f_in.write(loop_code)
        f_in.flush()

    times = []
    cmd = [str(jit_bin), in_path]
    env = os.environ.copy()
    env["ULISP_QUIET"] = "1"
    for _ in range(iterations):
        t0 = time.perf_counter()
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        t1 = time.perf_counter()
        if res.returncode != 0:
            raise RuntimeError(f"JIT execution failed: {res.stderr}")
        times.append((t1 - t0) * 1000.0)

    os.remove(in_path)
    return {
        "mean_ms": statistics.mean(times),
        "std_ms": statistics.stdev(times) if len(times) > 1 else 0.0,
        "min_ms": min(times),
        "max_ms": max(times),
    }

def benchmark_aot_compiled_binary(compiler_bin, code, iterations=50, is_jit=False):
    with tempfile.NamedTemporaryFile("w", suffix=".scm", delete=False) as f_in, \
         tempfile.NamedTemporaryFile("w", suffix=".s", delete=False) as f_s, \
         tempfile.NamedTemporaryFile("w", suffix="", delete=False) as f_exe:
        in_path = f_in.name
        s_path = f_s.name
        exe_path = f_exe.name
        if is_jit:
            f_in.write("(!compile)\n" + code)
        else:
            f_in.write(code)
        f_in.flush()

    # Compile to .s
    with open(s_path, "w") as out_f:
        subprocess.run([str(compiler_bin), in_path], stdout=out_f, check=True)
    # Compile to ELF
    subprocess.run(["gcc", "-no-pie", "-O2", str(RUNTIME_C), s_path, "-o", exe_path], check=True)

    times = []
    cmd = [exe_path]
    env = os.environ.copy()
    env["ULISP_QUIET"] = "1"
    for _ in range(iterations):
        t0 = time.perf_counter()
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        t1 = time.perf_counter()
        if res.returncode != 0:
            raise RuntimeError(f"AOT execution failed: {res.stderr}")
        times.append((t1 - t0) * 1000.0)

    os.remove(in_path)
    os.remove(s_path)
    os.remove(exe_path)
    return {
        "mean_ms": statistics.mean(times),
        "std_ms": statistics.stdev(times) if len(times) > 1 else 0.0,
        "min_ms": min(times),
        "max_ms": max(times),
    }

def main():
    print("==========================================================================")
    print(" Benchmarking: ulisp/build/scheme-stage2 vs ulisp/bin/ulisp-jit")
    print("==========================================================================")

    # 1. Binary Size & Segment Comparison
    stage2_meta = get_binary_metrics(STAGE2_BIN)
    jit_meta = get_binary_metrics(ULISP_JIT_BIN)

    print("\n### 1. Binary Artifact Metrics")
    print(f"| Binary | File Size (bytes) | Text Segment | Data Segment | BSS Segment |")
    print(f"|---|---|---|---|---|")
    print(f"| `ulisp/build/scheme-stage2` | {stage2_meta['file_size']:,} | {stage2_meta['text']:,} | {stage2_meta['data']:,} | {stage2_meta['bss']:,} |")
    print(f"| `ulisp/bin/ulisp-jit`       | {jit_meta['file_size']:,} | {jit_meta['text']:,} | {jit_meta['data']:,} | {jit_meta['bss']:,} |")

    # 2. AOT Compilation Throughput
    # Workload A: Minimal constant expression
    code_simple = "(+ 40 2)\n"
    # Workload B: Recursive Factorial
    code_fact = """(define (fact n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))
(fact 10)
"""
    # Workload C: Fibonacci with auxiliary function
    code_fib = """(define (fib n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(fib 12)
"""

    print("\n### 2. AOT Compilation Speed (Throughput) [30 iterations]")
    print(f"| Workload | `scheme-stage2` Mean (ms) | `ulisp-jit` Mean (ms) | Overhead / Ratio |")
    print(f"|---|---|---|---|")

    for name, code in [("Simple `(+ 40 2)`", code_simple),
                       ("Recursive `(fact 10)`", code_fact),
                       ("Branching `(fib 12)`", code_fib)]:
        res_s2 = benchmark_aot_compile(STAGE2_BIN, code, iterations=30, is_jit=False)
        res_jit = benchmark_aot_compile(ULISP_JIT_BIN, code, iterations=30, is_jit=True)
        ratio = res_jit['mean_ms'] / res_s2['mean_ms']
        print(f"| {name} | {res_s2['mean_ms']:.2f} ± {res_s2['std_ms']:.2f} | {res_jit['mean_ms']:.2f} ± {res_jit['std_ms']:.2f} | {ratio:.2f}x |")

    # 3. Execution Latency: AOT Native Binary vs JIT-Accelerated In-Process Evaluation
    loop_code = """(let loop ((i 0) (sum 0))
  (if (< i 1000)
      (loop (+ i 1) (+ sum i))
      sum))
"""
    print("\n### 3. Execution Performance: AOT Standalone vs JIT Dynamic Evaluation [30 iterations]")
    aot_exec_res = benchmark_aot_compiled_binary(STAGE2_BIN, loop_code, iterations=30, is_jit=False)
    jit_exec_res = benchmark_jit_execution(ULISP_JIT_BIN, loop_code, iterations=30)
    print(f"| Mode | Mean Time (ms) | Min (ms) | Max (ms) | Notes |")
    print(f"|---|---|---|---|---|")
    print(f"| AOT Compiled Executable (scheme-stage2) | {aot_exec_res['mean_ms']:.2f} ± {aot_exec_res['std_ms']:.2f} | {aot_exec_res['min_ms']:.2f} | {aot_exec_res['max_ms']:.2f} | Pure assembly execution |")
    print(f"| JIT In-Process (`ulisp-jit`)           | {jit_exec_res['mean_ms']:.2f} ± {jit_exec_res['std_ms']:.2f} | {jit_exec_res['min_ms']:.2f} | {jit_exec_res['max_ms']:.2f} | Hot-loop recording + LIR JIT dispatch |")

    print("\n==========================================================================")
    print(" Benchmark completed successfully.")
    print("==========================================================================")

if __name__ == "__main__":
    main()
