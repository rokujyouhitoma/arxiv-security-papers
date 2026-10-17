#!/usr/bin/env python3
import subprocess
import time
import statistics

def bench():
    times = []
    out = None
    for i in range(10):
        t0 = time.perf_counter()
        res = subprocess.run(["./ulisp/build/test_loop_reg"], capture_output=True, text=True)
        t1 = time.perf_counter()
        assert res.returncode == 0, f"Error: {res.stderr}"
        out = res.stdout.strip()
        assert out == "499999500000", f"Unexpected output: {out}"
        times.append((t1 - t0) * 1000.0)

    mean_ms = statistics.mean(times)
    min_ms = min(times)
    std_ms = statistics.stdev(times) if len(times) > 1 else 0.0

    print("=======================================================")
    print(" Hot Loop Accumulation (loop_sum 1,000,000 iters) Benchmark")
    print("=======================================================")
    print(f" Output      : {out} (EXPECTED: 499999500000)")
    print(f" Mean Latency: {mean_ms:.2f} ms ± {std_ms:.2f} ms")
    print(f" Min Latency : {min_ms:.2f} ms")
    print(f" Previous    : 2.62 ms")
    speedup = 2.62 / mean_ms
    print(f" Speedup     : {speedup:.2f}x faster!")
    print("=======================================================")

if __name__ == "__main__":
    bench()
