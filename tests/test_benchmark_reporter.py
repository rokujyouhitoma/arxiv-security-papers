"""Comprehensive Test Suite for Performance Regression Detector and Benchmark Reporter.

Conforms to [DSN-33-06] Chapter 4 & Issue #903.
Tests Welch's t-test mathematical functions, regression detection, Japanese markdown reporting,
and security path traversal guards (CWE-22 / CWE-73 / CWE-400 / CWE-369).
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT_DIR = Path(__file__).resolve().parent.parent
REGRESSION_SCRIPT = ROOT_DIR / "tools" / "regression_detector.py"
REPORT_SCRIPT = ROOT_DIR / "tools" / "report_benchmarks.py"
LATEST_JSON = ROOT_DIR / "outputs" / "benchmarks" / "latest.json"


# -----------------------------------------------------------------------------
# 1. Mathematical & Statistical Unit Tests
# -----------------------------------------------------------------------------


def test_incbeta_symmetry_and_known_values():
    """Verify regularized incomplete beta function against known mathematical properties."""
    from tools.regression_detector import incbeta

    # Boundary conditions
    assert incbeta(1.0, 1.0, 0.0) == 0.0
    assert incbeta(1.0, 1.0, 1.0) == 1.0

    # I_x(1, 1) = x
    for x in [0.1, 0.25, 0.5, 0.75, 0.9]:
        assert math.isclose(incbeta(1.0, 1.0, x), x, rel_tol=1e-7)

    # I_0.5(a, a) = 0.5 (by symmetry)
    for a in [0.5, 1.0, 2.0, 5.0, 10.0]:
        assert math.isclose(incbeta(a, a, 0.5), 0.5, rel_tol=1e-7)


def test_student_t_sf_properties():
    """Verify Student's t survival function upper-tail probabilities."""
    from tools.regression_detector import student_t_sf

    # At t=0, upper tail probability is 0.5 for any df
    assert student_t_sf(0.0, df=1.0) == 0.5
    assert student_t_sf(0.0, df=10.0) == 0.5
    assert student_t_sf(0.0, df=100.0) == 0.5

    # Positive t has p < 0.5
    p_pos = student_t_sf(2.0, df=10.0)
    assert 0.0 < p_pos < 0.5

    # Negative t has p > 0.5
    p_neg = student_t_sf(-2.0, df=10.0)
    assert 0.5 < p_neg < 1.0
    assert math.isclose(p_pos + p_neg, 1.0, rel_tol=1e-7)


def test_welch_t_test_identical_distributions():
    """Verify Welch's t-test returns near-zero t and p ~ 0.5 for identical distributions."""
    from tools.regression_detector import welch_t_test

    s1 = [10.0, 10.1, 9.9, 10.0, 10.05]
    s2 = [10.0, 9.95, 10.05, 10.0, 9.9]
    t, df, p = welch_t_test(s1, s2)

    assert abs(t) < 1.5
    assert df > 1.0
    assert p > 0.2


def test_welch_t_test_significant_regression():
    """Verify Welch's t-test detects statistically significant slowdown."""
    from tools.regression_detector import welch_t_test

    base = [1.00, 1.02, 0.98, 1.01, 0.99]  # Mean: 1.0, Std: ~0.016
    cand = [1.20, 1.22, 1.18, 1.21, 1.19]  # Mean: 1.2 (+20%), Std: ~0.016
    t, df, p = welch_t_test(base, cand)

    assert t > 10.0
    assert df > 4.0
    assert p < 0.0001


def test_welch_t_test_zero_variance_guard():
    """Verify division-by-zero protection (CWE-369) when variance is zero."""
    from tools.regression_detector import welch_t_test

    # Identical with 0 variance
    t, df, p = welch_t_test([1.0, 1.0], [1.0, 1.0])
    assert t == 0.0
    assert p == 0.5

    # Difference with 0 variance
    t, df, p = welch_t_test([1.0, 1.0], [2.0, 2.0])
    assert t > 0
    assert p == 0.0


# -----------------------------------------------------------------------------
# 2. Regression Evaluation Engine Tests
# -----------------------------------------------------------------------------


def test_evaluate_tier_regression_status():
    """Verify tier regression categorization (PASS, WARNING, REGRESSION)."""
    from tools.regression_detector import evaluate_tier_regression

    # 1. Faster -> PASS
    b1 = {"mean_ms": 10.0, "std_ms": 0.5, "raw_samples_ms": [10.0, 9.8, 10.2]}
    c1 = {"mean_ms": 8.0, "std_ms": 0.4, "raw_samples_ms": [8.0, 7.8, 8.2]}
    res1 = evaluate_tier_regression("ulisp_aot", b1, c1, threshold=0.05)
    assert res1["status"] == "PASS"
    assert "Speedup" in res1["reason"]

    # 2. Minor fluctuation (+3% < 5%) -> PASS
    c2 = {"mean_ms": 10.3, "std_ms": 0.5, "raw_samples_ms": [10.3, 10.1, 10.5]}
    res2 = evaluate_tier_regression("ulisp_aot", b1, c2, threshold=0.05)
    assert res2["status"] == "PASS"

    # 3. Clear regression (+25%, low variance, p < 0.05) -> REGRESSION
    b3 = {
        "mean_ms": 1.0,
        "std_ms": 0.02,
        "raw_samples_ms": [0.98, 1.02, 1.00, 1.01, 0.99],
    }
    c3 = {
        "mean_ms": 1.25,
        "std_ms": 0.02,
        "raw_samples_ms": [1.23, 1.27, 1.25, 1.24, 1.26],
    }
    res3 = evaluate_tier_regression("ulisp_aot", b3, c3, threshold=0.05)
    assert res3["status"] == "REGRESSION"
    assert res3["p_value"] < 0.05

    # 4. Large slowdown (+15%), but huge variance (p >= 0.05) -> WARNING
    b4 = {"mean_ms": 10.0, "std_ms": 5.0, "raw_samples_ms": [5.0, 15.0, 10.0]}
    c4 = {"mean_ms": 11.5, "std_ms": 6.0, "raw_samples_ms": [6.0, 17.0, 11.5]}
    res4 = evaluate_tier_regression("ulisp_aot", b4, c4, threshold=0.05)
    assert res4["status"] == "WARNING"


# -----------------------------------------------------------------------------
# 3. CLI Execution and Exit Code Tests
# -----------------------------------------------------------------------------


def test_regression_detector_cli_clean():
    """Verify regression detector exits with code 0 on identical baseline."""
    if not LATEST_JSON.exists():
        pytest.skip("outputs/benchmarks/latest.json does not exist")

    cmd = [
        sys.executable,
        str(REGRESSION_SCRIPT),
        "--baseline",
        str(LATEST_JSON),
        "--candidate",
        str(LATEST_JSON),
        "--threshold",
        "0.05",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert res.returncode == 0
    assert "OVERALL STATUS: 🟢 PASS" in res.stdout


def test_regression_detector_cli_detects_regression():
    """Verify regression detector exits with code 1 when regression is injected."""
    if not LATEST_JSON.exists():
        pytest.skip("outputs/benchmarks/latest.json does not exist")

    with open(LATEST_JSON, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Inject +50% latency slowdown into candidate AOT
    for r in data["results"]:
        r["ulisp_aot"]["mean_ms"] *= 1.50
        r["ulisp_aot"]["raw_samples_ms"] = [
            x * 1.50
            for x in r["ulisp_aot"].get("raw_samples_ms", [r["ulisp_aot"]["mean_ms"]])
        ]

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp_cand:
        json.dump(data, tmp_cand)
        tmp_path = Path(tmp_cand.name)

    try:
        cmd = [
            sys.executable,
            str(REGRESSION_SCRIPT),
            "--baseline",
            str(LATEST_JSON),
            "--candidate",
            str(tmp_path),
            "--threshold",
            "0.05",
        ]
        res = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert res.returncode == 1
        assert "OVERALL STATUS: 🔴 REGRESSION" in res.stdout
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def test_regression_detector_missing_file_exit_code_2():
    """Verify exit code 2 on missing input file."""
    cmd = [
        sys.executable,
        str(REGRESSION_SCRIPT),
        "--baseline",
        "outputs/benchmarks/non_existent_baseline.json",
        "--candidate",
        "outputs/benchmarks/non_existent_cand.json",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert res.returncode == 2


# -----------------------------------------------------------------------------
# 4. Japanese Markdown Report Generator Tests
# -----------------------------------------------------------------------------


def test_report_benchmarks_generation_and_relative_links():
    """Verify Japanese markdown report generates all 5 sections and has 0 absolute paths."""
    from tools.report_benchmarks import generate_japanese_markdown_report

    mock_latest = {
        "timestamp": "2026-11-21 12:00:00",
        "system": {
            "os": "Linux",
            "arch": "x86_64",
            "processor": "x86_64",
            "python_version": "3.11.0",
        },
        "config": {"iterations": 5},
        "results": [
            {
                "workload_id": "fib_loop",
                "title": "Iterative Fibonacci (fib 20)",
                "description": "Fibonacci test",
                "iterations": 5,
                "correctness": {
                    "ilisp_valid": True,
                    "aot_valid": True,
                    "jit_valid": True,
                    "expected": "6765",
                    "actual_ilisp": "6765",
                    "actual_aot": "6765",
                    "actual_jit": "6765",
                },
                "ilisp": {
                    "mean_ms": 80.0,
                    "std_ms": 2.0,
                    "min_ms": 78.0,
                    "max_ms": 82.0,
                },
                "ulisp_aot": {
                    "compile_ms": 10.0,
                    "mean_ms": 0.5,
                    "std_ms": 0.05,
                    "min_ms": 0.45,
                    "max_ms": 0.55,
                },
                "ulisp_jit": {
                    "mean_ms": 8.0,
                    "std_ms": 0.5,
                    "min_ms": 7.5,
                    "max_ms": 8.5,
                },
                "speedups": {
                    "aot_vs_ilisp": 160.0,
                    "jit_vs_ilisp": 10.0,
                    "aot_vs_jit": 16.0,
                },
            }
        ],
    }

    mock_history = [mock_latest]
    mock_regression = {
        "status": "PASS",
        "threshold_percent": 5.0,
        "p_value_threshold": 0.05,
        "workloads": [
            {
                "workload_id": "fib_loop",
                "title": "Iterative Fibonacci (fib 20)",
                "status": "PASS",
                "tiers": {
                    "ulisp_aot": {
                        "tier": "ulisp_aot",
                        "base_mean_ms": 0.5,
                        "cand_mean_ms": 0.49,
                        "delta_percent": -2.0,
                        "t_statistic": -0.2,
                        "p_value": 0.55,
                        "status": "PASS",
                        "reason": "Speedup of 2.0%",
                    }
                },
            }
        ],
    }

    report = generate_japanese_markdown_report(
        mock_latest, mock_history, mock_regression
    )

    # Section Headers
    assert (
        "# ILisp vs ULisp AOT vs ULisp JIT 3種実行系 継続的性能評価レポート" in report
    )
    assert "## 1. 総合評価エグゼクティブサマリー" in report
    assert "## 2. 統計的性能退行分析 (Welch's t-test Regression Analysis)" in report
    assert "## 3. 時系列トレンド推移 (Historical Trend Analysis)" in report
    assert "## 4. ワークロード別詳細分析" in report
    assert "## 5. アーキテクチャ階層と性能特性ダイアグラム" in report

    # Japanese table entries
    assert "Iterative Fibonacci" in report
    assert "160.0x" in report
    assert "🟢 100% PASS" in report
    assert "```mermaid" in report

    # Zero absolute path guarantee
    assert "/workspace" not in report
    assert "/root" not in report


# -----------------------------------------------------------------------------
# 5. Security Validation Tests (CWE-22 / CWE-73 / CWE-400)
# -----------------------------------------------------------------------------


def test_security_path_traversal_rejection():
    """Verify validate_path raises ValueError on path traversal attempts (CWE-22 / CWE-73)."""
    from tools.regression_detector import validate_path as reg_validate
    from tools.report_benchmarks import validate_path as rep_validate

    traversal_targets = [
        "../../../../etc/passwd",
        "../../var/log/syslog",
        "/etc/shadow",
    ]
    for target in traversal_targets:
        with pytest.raises(ValueError, match="Security Alert"):
            reg_validate(target)
        with pytest.raises(ValueError, match="Security Alert"):
            rep_validate(target)
