#!/usr/bin/env python3
"""
Performance & Memory Profiling Framework for 4-Tier Pure Python Vector Database.
Measures wall-clock time, CPU time, memory allocation (tracemalloc), latency percentiles,
and throughput (ops/sec) with zero external dependencies.
"""

import gc
import statistics
import time
import tracemalloc
from typing import Any, Callable, Dict, List, Optional


class ProfileResult:
    """Stores metrics for a single profiling run."""

    def __init__(
        self,
        name: str,
        iterations: int,
        total_time_ms: float,
        latencies_ms: List[float],
        memory_peak_kb: float,
        memory_delta_kb: float,
        extra_metrics: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.name = name
        self.iterations = iterations
        self.total_time_ms = total_time_ms
        self.latencies_ms = sorted(latencies_ms)
        self.memory_peak_kb = memory_peak_kb
        self.memory_delta_kb = memory_delta_kb
        self.extra_metrics = extra_metrics or {}

    @property
    def throughput_ops_sec(self) -> float:
        if self.total_time_ms <= 0:
            return 0.0
        return round((self.iterations / (self.total_time_ms / 1000.0)), 2)

    @property
    def mean_latency_ms(self) -> float:
        if not self.latencies_ms:
            return 0.0
        return round(statistics.mean(self.latencies_ms), 4)

    @property
    def p50_ms(self) -> float:
        return self._percentile(50)

    @property
    def p90_ms(self) -> float:
        return self._percentile(90)

    @property
    def p95_ms(self) -> float:
        return self._percentile(95)

    @property
    def p99_ms(self) -> float:
        return self._percentile(99)

    def _percentile(self, p: float) -> float:
        if not self.latencies_ms:
            return 0.0
        idx = int(len(self.latencies_ms) * (p / 100.0))
        idx = min(idx, len(self.latencies_ms) - 1)
        return round(self.latencies_ms[idx], 4)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "iterations": self.iterations,
            "total_time_ms": round(self.total_time_ms, 2),
            "throughput_ops_sec": self.throughput_ops_sec,
            "mean_latency_ms": self.mean_latency_ms,
            "p50_ms": self.p50_ms,
            "p90_ms": self.p90_ms,
            "p95_ms": self.p95_ms,
            "p99_ms": self.p99_ms,
            "memory_peak_kb": round(self.memory_peak_kb, 2),
            "memory_delta_kb": round(self.memory_delta_kb, 2),
            "extra_metrics": self.extra_metrics,
        }


class DatabaseProfiler:
    """
    High-precision profiler for database operations, memory allocations,
    and latency distribution analysis.
    """

    def __init__(self) -> None:
        self.results: List[ProfileResult] = []

    def profile_callable(
        self,
        name: str,
        fn: Callable[[], Any],
        iterations: int = 100,
        warmup: int = 5,
        extra_metrics: Optional[Dict[str, Any]] = None,
    ) -> ProfileResult:
        """
        Executes a callable with warm-up, tracemalloc, and per-call latency tracking.
        """
        gc.collect()

        # Warmup phase
        for _ in range(warmup):
            fn()

        gc.collect()
        tracemalloc.start()
        start_mem, _ = tracemalloc.get_traced_memory()

        latencies: List[float] = []
        start_total = time.perf_counter()

        for _ in range(iterations):
            t0 = time.perf_counter()
            fn()
            t1 = time.perf_counter()
            latencies.append((t1 - t0) * 1000.0)

        end_total = time.perf_counter()
        current_mem, peak_mem = tracemalloc.get_traced_memory()
        tracemalloc.stop()

        total_time_ms = (end_total - start_total) * 1000.0
        memory_peak_kb = peak_mem / 1024.0
        memory_delta_kb = (current_mem - start_mem) / 1024.0

        res = ProfileResult(
            name=name,
            iterations=iterations,
            total_time_ms=total_time_ms,
            latencies_ms=latencies,
            memory_peak_kb=memory_peak_kb,
            memory_delta_kb=memory_delta_kb,
            extra_metrics=extra_metrics,
        )
        self.results.append(res)
        return res

    def check_memory_leak(
        self,
        name: str,
        fn: Callable[[], Any],
        batches: int = 10,
        batch_size: int = 100,
        tolerance_kb_per_batch: float = 10.0,
    ) -> Dict[str, Any]:
        """
        Executes multiple batches of operations and measures memory slope to detect leaks.
        """
        gc.collect()
        tracemalloc.start()

        batch_memories: List[float] = []
        for _ in range(batches):
            for _ in range(batch_size):
                fn()
            gc.collect()
            cur_mem, _ = tracemalloc.get_traced_memory()
            batch_memories.append(cur_mem / 1024.0)

        tracemalloc.stop()

        # Calculate memory delta between first batch and final batch
        total_delta_kb = batch_memories[-1] - batch_memories[0]
        avg_delta_per_batch_kb = total_delta_kb / max(1, batches - 1)
        is_leak = avg_delta_per_batch_kb > tolerance_kb_per_batch

        return {
            "name": name,
            "total_operations": batches * batch_size,
            "batch_memories_kb": [round(m, 2) for m in batch_memories],
            "total_delta_kb": round(total_delta_kb, 2),
            "avg_delta_per_batch_kb": round(avg_delta_per_batch_kb, 2),
            "is_leak": is_leak,
        }
