#!/usr/bin/env python3
"""
Standard Library Observability & Profiling Framework (DSN-09).
Provides zero-dependency metrics collection, deterministic profiling, memory tracking,
micro-benchmarking, and bytecode inspection:
- time: perf_counter() (Wall-clock) & process_time() (CPU time)
- tracemalloc: Peak RAM and allocation tracking
- cProfile & pstats: Deterministic bottleneck function profiling
- timeit: Micro-benchmarking with multiple iterations
- dis: Bytecode disassembly & instruction analysis
"""

import cProfile
import dis
import io
import pstats
import time
import timeit
import tracemalloc
from typing import Any, Callable, Dict, List, Optional, Tuple


class ExecutionMetrics:
    """Stores measured execution time and memory allocation metrics."""

    def __init__(
        self,
        name: str,
        wall_time_ms: float = 0.0,
        cpu_time_ms: float = 0.0,
        current_memory_kb: float = 0.0,
        peak_memory_kb: float = 0.0,
        memory_delta_kb: float = 0.0,
    ) -> None:
        self.name = name
        self.wall_time_ms = round(wall_time_ms, 3)
        self.cpu_time_ms = round(cpu_time_ms, 3)
        self.current_memory_kb = round(current_memory_kb, 3)
        self.peak_memory_kb = round(peak_memory_kb, 3)
        self.memory_delta_kb = round(memory_delta_kb, 3)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "wall_time_ms": self.wall_time_ms,
            "cpu_time_ms": self.cpu_time_ms,
            "current_memory_kb": self.current_memory_kb,
            "peak_memory_kb": self.peak_memory_kb,
            "memory_delta_kb": self.memory_delta_kb,
        }

    def __repr__(self) -> str:
        return (
            f"ExecutionMetrics(name='{self.name}', wall={self.wall_time_ms}ms, "
            f"cpu={self.cpu_time_ms}ms, peak_mem={self.peak_memory_kb}KB, delta_mem={self.memory_delta_kb}KB)"
        )


class ExecutionProfiler:
    """
    Context manager for measuring wall-clock time, CPU time, and peak memory allocation.
    """

    def __init__(self, name: str = "operation", track_memory: bool = True) -> None:
        self.name = name
        self.track_memory = track_memory
        self.metrics: Optional[ExecutionMetrics] = None
        self._start_wall: float = 0.0
        self._start_cpu: float = 0.0
        self._start_memory_bytes: int = 0
        self._was_tracemalloc_running: bool = False

    def __enter__(self) -> "ExecutionProfiler":
        if self.track_memory:
            self._was_tracemalloc_running = tracemalloc.is_tracing()
            if not self._was_tracemalloc_running:
                tracemalloc.start()
            tracemalloc.reset_peak()
            cur, _ = tracemalloc.get_traced_memory()
            self._start_memory_bytes = cur

        self._start_cpu = time.process_time()
        self._start_wall = time.perf_counter()
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        end_wall = time.perf_counter()
        end_cpu = time.process_time()

        wall_ms = (end_wall - self._start_wall) * 1000.0
        cpu_ms = (end_cpu - self._start_cpu) * 1000.0

        current_kb = 0.0
        peak_kb = 0.0
        delta_kb = 0.0
        if self.track_memory:
            cur, peak = tracemalloc.get_traced_memory()
            current_kb = cur / 1024.0
            peak_kb = peak / 1024.0
            delta_kb = (cur - self._start_memory_bytes) / 1024.0
            if not self._was_tracemalloc_running:
                tracemalloc.stop()

        self.metrics = ExecutionMetrics(
            name=self.name,
            wall_time_ms=wall_ms,
            cpu_time_ms=cpu_ms,
            current_memory_kb=current_kb,
            peak_memory_kb=peak_kb,
            memory_delta_kb=delta_kb,
        )


def profile_function(
    func: Callable[..., Any],
    *args: Any,
    top_n: int = 10,
    sort_by: str = "cumtime",
    **kwargs: Any,
) -> Tuple[Any, str]:
    """
    Executes a function under cProfile and returns (result, formatted_pstats_summary).
    """
    profiler = cProfile.Profile()
    profiler.enable()
    result = func(*args, **kwargs)
    profiler.disable()

    s = io.StringIO()
    ps = pstats.Stats(profiler, stream=s).sort_stats(sort_by)
    ps.print_stats(top_n)
    return result, s.getvalue()


def benchmark_function(
    func: Callable[..., Any],
    number: int = 100,
    repeat: int = 3,
    *args: Any,
    **kwargs: Any,
) -> Dict[str, Any]:
    """
    Runs micro-benchmarking using timeit.repeat.
    """
    timer = timeit.Timer(lambda: func(*args, **kwargs))
    times = timer.repeat(repeat=repeat, number=number)
    avg_time_ms = (sum(times) / len(times) / number) * 1000.0
    min_time_ms = (min(times) / number) * 1000.0

    return {
        "iterations_per_run": number,
        "repeats": repeat,
        "min_time_ms": round(min_time_ms, 5),
        "avg_time_ms": round(avg_time_ms, 5),
        "raw_times_sec": [round(t, 5) for t in times],
    }


def analyze_bytecode(func: Callable[..., Any]) -> Dict[str, Any]:
    """
    Disassembles a function using the dis standard library to count instructions.
    """
    instructions: List[Dict[str, Any]] = []
    for instr in dis.get_instructions(func):
        instructions.append(
            {
                "opname": instr.opname,
                "opcode": instr.opcode,
                "argval": str(instr.argval),
                "offset": instr.offset,
            }
        )

    return {
        "function_name": getattr(func, "__name__", "anonymous"),
        "total_instructions": len(instructions),
        "instructions": instructions,
    }
