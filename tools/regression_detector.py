#!/usr/bin/env python3
"""Statistical Performance Regression Detector for ILisp, ULisp AOT, and ULisp JIT.

Conforms to [DSN-33-06] Chapter 4 & Issue #903.
Implements Welch's t-test with zero external dependencies to detect >= 5% latency regressions.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_THRESHOLD = 0.05  # 5% slowdown threshold
DEFAULT_P_VALUE = 0.05  # 95% confidence level
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5MB DoS protection (CWE-400)


def validate_path(path_str: str) -> Path:
    """Validate and sanitize paths to prevent path traversal (CWE-22 / CWE-73)."""
    p = Path(path_str)
    resolved = (ROOT_DIR / p).resolve() if not p.is_absolute() else p.resolve()
    try:
        resolved.relative_to(ROOT_DIR)
    except ValueError:
        # If absolute path points outside repo, allow only if existing file in /tmp for tests, else reject
        if not (resolved.is_relative_to(Path("/tmp")) and resolved.exists()):
            raise ValueError(f"Security Alert: Path {path_str} traverses outside repository root (CWE-22)")
    return resolved


# -----------------------------------------------------------------------------
# Pure Python Statistical Functions (Welch's t-test & Incomplete Beta)
# -----------------------------------------------------------------------------

def _betacf(a: float, b: float, x: float, max_iter: int = 100, eps: float = 3.0e-12) -> float:
    """Continued fraction for regularized incomplete beta function (Lentz's method)."""
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < eps:
        d = eps
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        # Even step
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < eps:
            d = eps
        c = 1.0 + aa / c
        if abs(c) < eps:
            c = eps
        d = 1.0 / d
        h *= d * c

        # Odd step
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < eps:
            d = eps
        c = 1.0 + aa / c
        if abs(c) < eps:
            c = eps
        d = 1.0 / d
        del_h = d * c
        h *= del_h
        if abs(del_h - 1.0) < eps:
            break
    return h


def incbeta(a: float, b: float, x: float) -> float:
    """Compute regularized incomplete beta function I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0

    # Symmetry transformation for rapid convergence
    factor = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log(1.0 - x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return factor * _betacf(a, b, x) / a
    else:
        return 1.0 - factor * _betacf(b, a, 1.0 - x) / b


def student_t_sf(t: float, df: float) -> float:
    """Survival function (one-tailed upper tail p-value P(T >= t)) for Student's t-distribution."""
    if df <= 0.0:
        return 1.0
    if t == 0.0:
        return 0.5
    if df > 100.0:
        # Standard normal approximation for large degrees of freedom
        return 0.5 * math.erfc(t / math.sqrt(2.0))

    x = df / (df + t * t)
    prob = 0.5 * incbeta(0.5 * df, 0.5, x)
    return prob if t > 0.0 else 1.0 - prob


def welch_t_test(
    sample1: List[float],
    sample2: List[float],
    mean1: Optional[float] = None,
    std1: Optional[float] = None,
    n1: Optional[int] = None,
    mean2: Optional[float] = None,
    std2: Optional[float] = None,
    n2: Optional[int] = None,
) -> Tuple[float, float, float]:
    """Perform Welch's t-test comparing sample2 (candidate) against sample1 (baseline).

    Returns:
        (t_statistic, degrees_of_freedom, p_value_upper_tail)
        p_value_upper_tail is the probability that candidate is slower due to chance alone.
    """
    # 1. Compute summary statistics
    if sample1 and len(sample1) >= 2:
        n1 = len(sample1)
        mean1 = sum(sample1) / n1
        var1 = sum((x - mean1) ** 2 for x in sample1) / (n1 - 1)
    else:
        n1 = n1 or (len(sample1) if sample1 else 1)
        mean1 = mean1 if mean1 is not None else (sample1[0] if sample1 else 0.0)
        var1 = (std1 or 0.0) ** 2

    if sample2 and len(sample2) >= 2:
        n2 = len(sample2)
        mean2 = sum(sample2) / n2
        var2 = sum((x - mean2) ** 2 for x in sample2) / (n2 - 1)
    else:
        n2 = n2 or (len(sample2) if sample2 else 1)
        mean2 = mean2 if mean2 is not None else (sample2[0] if sample2 else 0.0)
        var2 = (std2 or 0.0) ** 2

    # Division by zero guards (CWE-369)
    if n1 <= 1 or n2 <= 1:
        # Insufficient degrees of freedom for Welch's t-test
        diff = mean2 - mean1
        return (0.0, 1.0, 0.5 if abs(diff) < 1e-9 else (0.001 if diff > 0 else 0.999))

    se1 = var1 / n1
    se2 = var2 / n2
    se_total = math.sqrt(se1 + se2)

    if se_total < 1e-12:
        # Near-zero variance
        diff = mean2 - mean1
        if abs(diff) < 1e-12:
            return (0.0, float(n1 + n2 - 2), 0.5)
        elif diff > 0:
            return (999.0, float(n1 + n2 - 2), 0.0)
        else:
            return (-999.0, float(n1 + n2 - 2), 1.0)

    t_stat = (mean2 - mean1) / se_total

    # Welch–Satterthwaite equation for degrees of freedom
    denom = (se1 ** 2) / (n1 - 1) + (se2 ** 2) / (n2 - 1)
    df = (se1 + se2) ** 2 / denom if denom > 1e-12 else 1.0
    df = max(1.0, df)

    p_val = student_t_sf(t_stat, df)
    return (t_stat, df, p_val)


# -----------------------------------------------------------------------------
# Regression Evaluation Engine
# -----------------------------------------------------------------------------

def evaluate_tier_regression(
    tier_name: str,
    base_tier: Dict[str, Any],
    cand_tier: Dict[str, Any],
    threshold: float = DEFAULT_THRESHOLD,
    p_value_threshold: float = DEFAULT_P_VALUE,
) -> Dict[str, Any]:
    """Evaluate whether candidate tier exhibits a performance regression against baseline tier."""
    base_mean = float(base_tier.get("mean_ms", 0.0))
    cand_mean = float(cand_tier.get("mean_ms", 0.0))

    base_samples = [float(x) for x in base_tier.get("raw_samples_ms", [])]
    cand_samples = [float(x) for x in cand_tier.get("raw_samples_ms", [])]

    base_std = float(base_tier.get("std_ms", 0.0))
    cand_std = float(cand_tier.get("std_ms", 0.0))

    base_n = len(base_samples) if base_samples else int(base_tier.get("iterations", 1))
    cand_n = len(cand_samples) if cand_samples else int(cand_tier.get("iterations", 1))

    # Delta ratio (CWE-369 guard)
    if base_mean <= 1e-9:
        delta_ratio = 0.0
    else:
        delta_ratio = (cand_mean - base_mean) / base_mean

    t_stat, df, p_val = welch_t_test(
        base_samples,
        cand_samples,
        mean1=base_mean,
        std1=base_std,
        n1=base_n,
        mean2=cand_mean,
        std2=cand_std,
        n2=cand_n,
    )

    # Determine status
    # 1. Candidate is faster or equal
    if delta_ratio <= 0.0:
        status = "PASS"
        reason = f"Speedup of {abs(delta_ratio) * 100:.1f}% (improved)"
    # 2. Slowdown is below threshold (< 5%)
    elif delta_ratio < threshold:
        status = "PASS"
        reason = f"Fluctuation of +{delta_ratio * 100:.1f}% is within acceptable threshold (+{threshold * 100:.0f}%)"
    # 3. Slowdown >= threshold: check statistical significance
    else:
        has_stats = (base_n >= 2 and cand_n >= 2)
        if has_stats:
            if p_val < p_value_threshold:
                status = "REGRESSION"
                reason = (
                    f"Statistically significant slowdown of +{delta_ratio * 100:.1f}% "
                    f"({base_mean:.2f}ms -> {cand_mean:.2f}ms, t={t_stat:.2f}, p={p_val:.4f} < {p_value_threshold})"
                )
            else:
                status = "WARNING"
                reason = (
                    f"Latency increased by +{delta_ratio * 100:.1f}%, but variance is high "
                    f"(p={p_val:.4f} >= {p_value_threshold}, not statistically confirmed)"
                )
        else:
            # Single-run or summary-only comparison: evaluate purely on magnitude
            if delta_ratio >= threshold * 2.0:
                status = "REGRESSION"
                reason = f"Slowdown of +{delta_ratio * 100:.1f}% exceeds threshold (single sample, p-test N/A)"
            else:
                status = "WARNING"
                reason = f"Slowdown of +{delta_ratio * 100:.1f}% detected (single sample, p-test N/A)"

    return {
        "tier": tier_name,
        "base_mean_ms": base_mean,
        "cand_mean_ms": cand_mean,
        "delta_ratio": delta_ratio,
        "delta_percent": delta_ratio * 100.0,
        "t_statistic": t_stat,
        "degrees_of_freedom": df,
        "p_value": p_val,
        "status": status,
        "reason": reason,
    }


def detect_regressions(
    baseline_data: Dict[str, Any],
    candidate_data: Dict[str, Any],
    threshold: float = DEFAULT_THRESHOLD,
    p_value_threshold: float = DEFAULT_P_VALUE,
    evaluated_tiers: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Compare all workloads in candidate against baseline and generate regression analysis."""
    if evaluated_tiers is None:
        evaluated_tiers = ["ulisp_aot", "ulisp_jit"]

    base_map = {r["workload_id"]: r for r in baseline_data.get("results", [])}
    cand_results = candidate_data.get("results", [])

    workload_reports = []
    has_regression = False
    has_warning = False

    for cand in cand_results:
        wid = cand["workload_id"]
        title = cand.get("title", wid)
        if wid not in base_map:
            continue
        base = base_map[wid]

        tier_evals = {}
        workload_status = "PASS"

        for tier in evaluated_tiers:
            if tier in cand and tier in base:
                eval_res = evaluate_tier_regression(
                    tier,
                    base[tier],
                    cand[tier],
                    threshold=threshold,
                    p_value_threshold=p_value_threshold,
                )
                tier_evals[tier] = eval_res
                if eval_res["status"] == "REGRESSION":
                    workload_status = "REGRESSION"
                    has_regression = True
                elif eval_res["status"] == "WARNING" and workload_status != "REGRESSION":
                    workload_status = "WARNING"
                    has_warning = True

        workload_reports.append({
            "workload_id": wid,
            "title": title,
            "status": workload_status,
            "tiers": tier_evals,
        })

    overall_status = "REGRESSION" if has_regression else ("WARNING" if has_warning else "PASS")

    return {
        "status": overall_status,
        "threshold": threshold,
        "threshold_percent": threshold * 100.0,
        "p_value_threshold": p_value_threshold,
        "evaluated_tiers": evaluated_tiers,
        "workloads": workload_reports,
    }


def load_json_safe(file_path: Path) -> Dict[str, Any]:
    """Safely load JSON file with size check (CWE-400)."""
    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")
    size = file_path.stat().st_size
    if size > MAX_FILE_SIZE_BYTES:
        raise ValueError(f"File size {size} bytes exceeds limit of {MAX_FILE_SIZE_BYTES} bytes (CWE-400)")
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser(
        description="Statistical Performance Regression Detector for ILisp, ULisp AOT, and ULisp JIT"
    )
    parser.add_argument("--baseline", "-b", type=str, required=True, help="Path to baseline JSON file")
    parser.add_argument("--candidate", "-c", type=str, required=True, help="Path to candidate JSON file")
    parser.add_argument(
        "--threshold", "-t", type=float, default=DEFAULT_THRESHOLD, help="Regression threshold ratio (default: 0.05)"
    )
    parser.add_argument(
        "--p-value", "-p", type=float, default=DEFAULT_P_VALUE, help="Significance level p-value (default: 0.05)"
    )
    parser.add_argument(
        "--tiers",
        type=str,
        default="ulisp_aot,ulisp_jit",
        help="Comma-separated tiers to evaluate (default: ulisp_aot,ulisp_jit)",
    )
    parser.add_argument("--json-out", type=str, default="", help="Path to write regression report JSON")
    parser.add_argument("--strict", action="store_true", help="Fail with exit code 1 on WARNING as well as REGRESSION")
    args = parser.parse_args()

    try:
        base_path = validate_path(args.baseline)
        cand_path = validate_path(args.candidate)
        base_data = load_json_safe(base_path)
        cand_data = load_json_safe(cand_path)
    except Exception as e:
        print(f"[!] Error loading benchmark files: {e}", file=sys.stderr)
        sys.exit(2)

    tiers = [t.strip() for t in args.tiers.split(",") if t.strip()]
    report = detect_regressions(
        base_data,
        cand_data,
        threshold=args.threshold,
        p_value_threshold=args.p_value,
        evaluated_tiers=tiers,
    )

    # Print summary table
    print("=" * 80)
    print(" STATISTICAL PERFORMANCE REGRESSION REPORT (Welch's t-test)")
    print(f" Threshold: +{args.threshold * 100:.1f}% | Significance: p < {args.p_value:.2f}")
    print("=" * 80)

    for w in report["workloads"]:
        wid = w["workload_id"]
        w_status = w["status"]
        icon = "🟢" if w_status == "PASS" else ("🟡" if w_status == "WARNING" else "🔴")
        print(f"\n{icon} [{w_status}] {w['title']} ({wid}):")

        for tier, res in w["tiers"].items():
            t_icon = "✓" if res["status"] == "PASS" else ("!" if res["status"] == "WARNING" else "✗")
            delta_str = f"{res['delta_percent']:+.2f}%"
            t_str = f"t={res['t_statistic']:.2f}, p={res['p_value']:.4f}"
            print(
                f"   {t_icon} {tier:<10}: {res['base_mean_ms']:>6.2f}ms -> {res['cand_mean_ms']:>6.2f}ms "
                f"({delta_str:>7}) [{t_str}] => {res['reason']}"
            )

    print("\n" + "=" * 80)
    overall = report["status"]
    if overall == "PASS":
        print("[+] OVERALL STATUS: 🟢 PASS - No statistically significant regressions detected.")
    elif overall == "WARNING":
        print("[!] OVERALL STATUS: 🟡 WARNING - Potential slowdown observed, but statistical variance is high.")
    else:
        print("[x] OVERALL STATUS: 🔴 REGRESSION - Performance regression detected exceeding threshold!")
    print("=" * 80)

    # Optional JSON output
    if args.json_out:
        out_path = validate_path(args.json_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"\n[+] Saved regression evaluation JSON to: {out_path}")

    # Determine exit code
    if overall == "REGRESSION":
        sys.exit(1)
    elif overall == "WARNING" and args.strict:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
