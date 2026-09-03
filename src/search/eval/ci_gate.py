#!/usr/bin/env python3
"""
Continuous Integration IR Metrics Regression Quality Gate (Issue 133, DSN-10).
Evaluates search engine ranking accuracy against gold-standard benchmarks (NDCG@10, MRR, MAP)
and enforces automated failure thresholds to prevent search quality degradation.
"""

import argparse
import datetime
import hashlib
import json
import os
import sys
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

from .dataset import DEFAULT_SECURITY_GOLD_STANDARD, EvaluationQuery
from .evaluator import SearchEvaluator


class IRRegressionGate:
    """Automated CI Quality Gate checking for Information Retrieval metrics regressions."""

    DEFAULT_THRESHOLD_DROP = 0.03  # Max allowed relative drop: 3%

    def __init__(
        self,
        baseline_path: Optional[str] = None,
        queries: Optional[List[EvaluationQuery]] = None,
        top_k: int = 10,
        threshold_drop: float = DEFAULT_THRESHOLD_DROP,
    ) -> None:
        if baseline_path is None:
            baseline_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "baseline_metrics.json"
            )
        self.baseline_path = baseline_path
        self.queries = queries or DEFAULT_SECURITY_GOLD_STANDARD
        self.top_k = top_k
        self.threshold_drop = threshold_drop

    def load_baseline(self) -> Dict[str, Any]:
        """Loads commit-managed baseline metrics JSON."""
        if not os.path.exists(self.baseline_path):
            return {}
        try:
            with open(self.baseline_path, "r", encoding="utf-8") as f:
                data: Dict[str, Any] = json.load(f)
                return data
        except Exception as e:
            sys.stderr.write(
                f"Warning: Failed to read baseline {self.baseline_path}: {e}\n"
            )
            return {}

    def _compute_checksum(self, metrics_payload: Dict[str, Any]) -> str:
        serialized = json.dumps(metrics_payload, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(serialized.encode("utf-8")).hexdigest()

    def save_baseline(
        self,
        metrics: Dict[str, Any],
        commit_hash: str = "HEAD",
    ) -> None:
        """Saves verified search engine metrics as authoritative CI baseline."""
        payload = {
            "version": "1.0.0",
            "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "commit_hash": commit_hash,
            "top_k": self.top_k,
            "metrics": metrics,
        }
        payload["sha256"] = self._compute_checksum(metrics)
        with open(self.baseline_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)

    def evaluate_current(
        self,
        search_fn: Optional[Callable[[str, int], Sequence[str]]] = None,
    ) -> Dict[str, Any]:
        """Runs evaluation queries using deterministic ranking."""
        if search_fn is None:
            from ..vector_engine import VectorEngine

            engine = VectorEngine()

            def deterministic_search(query: str, top_k: int) -> Sequence[str]:
                # Search with expanded candidate pool and enforce strict tie-breaking
                raw_results = engine.search_rrf_hybrid(query, top_k=top_k * 2)
                # Sort primarily by score descending, secondarily by ID ascending
                sorted_results = sorted(
                    raw_results,
                    key=lambda d: (
                        -round(float(d.get("score", 0.0)), 6),
                        str(d.get("id", "")),
                    ),
                )
                return [str(d.get("id", "")) for d in sorted_results[:top_k]]

            search_fn = deterministic_search

        evaluator = SearchEvaluator(queries=self.queries, top_k=self.top_k)
        result: Dict[str, Any] = evaluator.evaluate(search_fn)
        return result

    def check_regression(
        self,
        current_summary: Dict[str, Any],
        baseline_metrics: Dict[str, Any],
    ) -> Tuple[bool, List[str]]:
        """
        Compares current summary against baseline metrics.
        Returns (is_passed, failure_reasons).
        """
        reasons: List[str] = []
        # Monitored core metrics
        metric_keys = [
            ("mean_NDCG_at_k", "NDCG@10"),
            ("MRR", "MRR"),
            ("MAP", "MAP"),
            ("mean_precision_at_k", "Precision@10"),
            ("mean_recall_at_k", "Recall@10"),
        ]

        for key, display_name in metric_keys:
            baseline_val = float(baseline_metrics.get(key, 0.0))
            current_val = float(current_summary.get(key, 0.0))

            if baseline_val > 0.0:
                rel_change = (current_val - baseline_val) / baseline_val
                if rel_change < -self.threshold_drop:
                    drop_pct = abs(rel_change) * 100.0
                    threshold_pct = self.threshold_drop * 100.0
                    reasons.append(
                        f"Regression detected in {display_name}: dropped by {drop_pct:.2f}% "
                        f"(current: {current_val:.4f}, baseline: {baseline_val:.4f}, "
                        f"max allowed drop: {threshold_pct:.1f}%)"
                    )

        is_passed = len(reasons) == 0
        return is_passed, reasons

    def _handle_baseline_write(self, current_summary: Dict[str, Any], msg: str) -> int:
        self.save_baseline(current_summary)
        print(msg)
        self._print_metrics_table(current_summary, {})
        return 0

    @staticmethod
    def _report_failure(reasons: List[str]) -> int:
        sys.stderr.write("\n=======================================================\n")
        sys.stderr.write("❌ [CI QUALITY GATE FAILED] IR METRICS REGRESSION DETECTED\n")
        sys.stderr.write("=======================================================\n")
        for reason in reasons:
            sys.stderr.write(f"  - {reason}\n")
        sys.stderr.write(
            "\nCorrect the search ranking changes or update baseline via:\n"
        )
        sys.stderr.write("  python -m src.search.eval.ci_gate --update-baseline\n")
        return 1

    def run_gate(
        self,
        search_fn: Optional[Callable[[str, int], Sequence[str]]] = None,
        update_baseline: bool = False,
    ) -> int:
        """Executes the gate check. Returns 0 on success, 1 on regression failure."""
        eval_result = self.evaluate_current(search_fn)
        current_summary: Dict[str, Any] = eval_result["summary"]

        if update_baseline:
            return self._handle_baseline_write(
                current_summary,
                f"Authoritative IR Baseline successfully updated at {self.baseline_path}",
            )

        baseline_data = self.load_baseline()
        if not baseline_data or "metrics" not in baseline_data:
            return self._handle_baseline_write(
                current_summary,
                "No existing baseline found. Writing initial baseline...",
            )

        baseline_metrics = baseline_data["metrics"]
        is_passed, reasons = self.check_regression(current_summary, baseline_metrics)
        self._print_metrics_table(current_summary, baseline_metrics)

        if not is_passed:
            return self._report_failure(reasons)

        print(
            "\n✅ [CI QUALITY GATE PASSED] All IR metrics meet or exceed baseline criteria."
        )
        return 0

    def _format_metric_row(self, label: str, cur_val: float, base_val: float) -> str:
        if base_val > 0.0:
            rel = ((cur_val - base_val) / base_val) * 100.0
            rel_str = f"{rel:+.2f}%"
            status = "PASS" if rel >= -self.threshold_drop * 100.0 else "FAIL"
        else:
            rel_str = "N/A"
            status = "BASELINE"

        row = [
            label.ljust(15),
            f"{cur_val:.4f}".ljust(15),
            f"{base_val:.4f}".ljust(15),
            rel_str.ljust(15),
            status.ljust(15),
        ]
        return " | ".join(row)

    def _print_metrics_table(
        self,
        current: Dict[str, Any],
        baseline: Dict[str, Any],
    ) -> None:
        headers = ["Metric", "Current", "Baseline", "Rel Change (%)", "Status"]
        print(f"\n{' | '.join(h.ljust(15) for h in headers)}")
        print("-" * 80)
        metrics_list = [
            ("mean_NDCG_at_k", f"NDCG@{self.top_k}"),
            ("MRR", "MRR"),
            ("MAP", "MAP"),
            ("mean_precision_at_k", f"Precision@{self.top_k}"),
            ("mean_recall_at_k", f"Recall@{self.top_k}"),
        ]
        for key, label in metrics_list:
            cur_val = float(current.get(key, 0.0))
            base_val = float(baseline.get(key, 0.0)) if baseline else 0.0
            print(self._format_metric_row(label, cur_val, base_val))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="IR Continuous Integration Regression Gate"
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="Update authoritative baseline metrics JSON",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.03,
        help="Maximum allowed relative drop (default 0.03 for 3 percent)",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=10,
        help="Evaluation ranking depth top_k (default 10)",
    )
    args = parser.parse_args()

    gate = IRRegressionGate(top_k=args.top_k, threshold_drop=args.threshold)
    sys.exit(gate.run_gate(update_baseline=args.update_baseline))


if __name__ == "__main__":
    main()
