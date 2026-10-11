"""Test suite for Trio Benchmark Engine (ILisp, ULisp AOT, ULisp JIT).

Conforms to Issue #515.
"""

import json
import tempfile
from pathlib import Path

import pytest

ROOT_DIR = Path(__file__).resolve().parent.parent
BENCHMARK_SCRIPT = ROOT_DIR / "tools" / "benchmark_ilisp_ulisp.py"
ULISP_JIT_BIN = ROOT_DIR / "ulisp" / "bin" / "ulisp-jit"
STAGE2_BIN = ROOT_DIR / "ulisp" / "build" / "scheme-stage2"


def test_ilisp_direct_execution():
    """Verify ILisp basic evaluation via CLI returns expected result."""
    from tools.benchmark_ilisp_ulisp import run_ilisp

    ms, out = run_ilisp("(+ 40 2)")
    assert ms > 0
    assert out == "42"


def test_markdown_report_generation():
    """Verify Markdown report generation contains expected structure and tables."""
    from tools.benchmark_ilisp_ulisp import generate_markdown_report

    dummy_data = {
        "timestamp": "2026-10-11 12:00:00",
        "system": {
            "os": "Linux",
            "arch": "x86_64",
            "processor": "x86_64",
            "python_version": "3.11.0",
        },
        "config": {"iterations": 5, "compiler": "scheme-stage2", "jit_bin": "ulisp-jit"},
        "results": [
            {
                "workload_id": "test_add",
                "title": "Simple Addition",
                "description": "Tests basic addition",
                "iterations": 5,
                "correctness": {
                    "ilisp_valid": True,
                    "aot_valid": True,
                    "jit_valid": True,
                    "expected": "42",
                    "actual_ilisp": "42",
                    "actual_aot": "42",
                    "actual_jit": "42",
                },
                "ilisp": {"mean_ms": 10.0, "std_ms": 1.0, "min_ms": 9.0, "max_ms": 11.0},
                "ulisp_aot": {"compile_ms": 50.0, "mean_ms": 1.0, "std_ms": 0.1, "min_ms": 0.9, "max_ms": 1.1},
                "ulisp_jit": {"mean_ms": 2.0, "std_ms": 0.2, "min_ms": 1.8, "max_ms": 2.2},
                "speedups": {"aot_vs_ilisp": 10.0, "jit_vs_ilisp": 5.0, "aot_vs_jit": 2.0},
            }
        ],
    }

    report = generate_markdown_report(dummy_data)
    assert "# ILisp vs ULisp AOT vs ULisp JIT" in report
    assert "Simple Addition" in report
    assert "10.0x" in report
    assert "```mermaid" in report


def test_regression_check_detection():
    """Verify regression checking correctly identifies slowed execution."""
    from tools.benchmark_ilisp_ulisp import check_regression

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        base_path = Path(f.name)
        json.dump(
            {
                "results": [
                    {
                        "workload_id": "fib_loop",
                        "ulisp_aot": {"mean_ms": 1.0},
                        "ulisp_jit": {"mean_ms": 2.0},
                    }
                ]
            },
            f,
        )

    try:
        # Current result with 2x slower AOT latency
        current = [
            {
                "workload_id": "fib_loop",
                "ulisp_aot": {"mean_ms": 2.5},  # > 1.0 * 1.5
                "ulisp_jit": {"mean_ms": 2.1},
            }
        ]
        warnings = check_regression(current, base_path, threshold=1.5)
        assert len(warnings) == 1
        assert "REGRESSION WARNING in fib_loop (ULisp AOT)" in warnings[0]
    finally:
        if base_path.exists():
            base_path.unlink()


def test_full_suite_single_iteration():
    """Verify end-to-end benchmark run for single workload with 1 iteration."""
    from tools.benchmark_ilisp_ulisp import WORKLOADS, measure_workload

    if not ULISP_JIT_BIN.exists():
        pytest.skip("ulisp-jit binary not compiled yet")

    spec = WORKLOADS["sum_loop"]
    res = measure_workload("sum_loop", spec, iterations=1, compiler_path=ULISP_JIT_BIN, jit_bin=ULISP_JIT_BIN)
    assert res["correctness"]["ilisp_valid"] is True
    assert res["correctness"]["aot_valid"] is True
    assert res["correctness"]["jit_valid"] is True
    assert res["ulisp_aot"]["mean_ms"] > 0
    assert res["ulisp_jit"]["mean_ms"] > 0
