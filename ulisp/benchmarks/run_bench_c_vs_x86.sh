#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ULISP_DIR="$(cd "$DIR/.." && pwd)"
ROOT_DIR="$(cd "$ULISP_DIR/.." && pwd)"
export PYTHONPATH="$ROOT_DIR"
cd "$ULISP_DIR"

PYTHON="$ROOT_DIR/.venv/bin/python3"
if [ ! -x "$PYTHON" ]; then
    PYTHON="python3"
fi
ILISP="$PYTHON -m ilisp"
COMPILER="compiler.scm"

BUILD_DIR="build/bench_c_x86"
mkdir -p "$BUILD_DIR"

echo "================================================================================"
echo " ULisp Performance Benchmark: x86-64 Native Bare-Metal vs Portable C (-O2)"
echo " OS: $(uname -s) $(uname -m), Compiler: gcc $(gcc -dumpversion)"
echo "================================================================================"

run_bench() {
    local name="$1"
    local expr="$2"
    local iters="${3:-5}"

    local s_file="$BUILD_DIR/${name}.s"
    local c_file="$BUILD_DIR/${name}.c"
    local bin_x86="$BUILD_DIR/${name}_x86"
    local bin_c="$BUILD_DIR/${name}_c"

    echo ""
    echo ">>> Workload: $name (Iterations: $iters)"

    # 1. Compile x86-64
    printf "%s\n" "$expr" | $ILISP "$COMPILER" > "$s_file"
    gcc -nostdlib -static "$s_file" -o "$bin_x86"
    local x86_size=$(wc -c < "$bin_x86")

    # 2. Compile Portable C
    printf "(!target c)\n%s\n" "$expr" | $ILISP "$COMPILER" > "$c_file"
    gcc -Wall -Wextra -Werror -Wno-unused-label -O2 "$c_file" -o "$bin_c"
    local c_size=$(wc -c < "$bin_c")

    # Verify correctness
    local out_x86=$("$bin_x86")
    local out_c=$("$bin_c")
    if [ "$out_x86" != "$out_c" ]; then
        echo "ERROR: Output mismatch! x86='$out_x86' vs C='$out_c'"
        exit 1
    fi
    echo "    Output verified: $out_x86 (Binary Size: x86=${x86_size}B, C=${c_size}B)"

    # 3. Benchmark Execution using Python precision timer
    $PYTHON -c '
import subprocess, time, statistics, sys

bin_x86 = sys.argv[1]
bin_c = sys.argv[2]
iters = int(sys.argv[3])

def measure(bin_path):
    times = []
    for _ in range(iters):
        t0 = time.perf_counter_ns()
        subprocess.run([bin_path], stdout=subprocess.PIPE, check=True)
        t1 = time.perf_counter_ns()
        times.append((t1 - t0) / 1_000_000.0) # ms
    return statistics.mean(times), min(times), statistics.stdev(times) if len(times) > 1 else 0.0

m_x86, min_x86, std_x86 = measure(bin_x86)
m_c, min_c, std_c = measure(bin_c)

ratio = m_c / m_x86 if m_x86 > 0 else 1.0
winner = "C is FASTER" if ratio < 1.0 else "x86-64 is FASTER"

print(f"    x86-64 Native:  {m_x86:8.2f} ms (min: {min_x86:8.2f} ms, std: {std_x86:5.2f} ms)")
print(f"    Portable C:     {m_c:8.2f} ms (min: {min_c:8.2f} ms, std: {std_c:5.2f} ms)")
print(f"    => Ratio (C/x86): {ratio:.2f}x ({winner})")
' "$bin_x86" "$bin_c" "$iters"
}

# --- Workload Definitions ---

# 1. Fibonacci (fib 30) - Recursive branching and call-frame overhead
run_bench "fib_30" "(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))" 3

# 2. Tail-Recursive Loop (10,000,000 iterations) - TCO, register allocation & loop speed
run_bench "loop_10m" "(letrec ((loop (lambda (i acc) (if (= i 10000000) acc (loop (+ i 1) (+ acc i)))))) (loop 0 0))" 5

# 3. Higher-Order Closures (1,000,000 calls) - First-class closure calls
run_bench "closure_1m" "(letrec ((iter (lambda (n f acc) (if (= n 0) acc (iter (- n 1) f (f acc)))))) (iter 1000000 (lambda (x) (+ x 1)) 0))" 5

# 4. List Allocation & Traversal (100,000 pairs) - Heap bump allocation and pointer traversal
run_bench "list_100k" "(letrec ((iota (lambda (n acc) (if (= n 0) acc (iota (- n 1) (cons n acc))))) (sum (lambda (lst acc) (if (pair? lst) (sum (cdr lst) (+ acc (car lst))) acc)))) (sum (iota 100000 ()) 0))" 5

echo ""
echo "================================================================================"
echo " Benchmark suite completed successfully!"
echo "================================================================================"


