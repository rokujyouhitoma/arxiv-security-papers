import os
import tempfile

from src.search.eval.ci_gate import IRRegressionGate
from src.search.eval.dataset import EvaluationQuery


def test_check_regression_pass_and_fail():
    gate = IRRegressionGate(threshold_drop=0.03)

    baseline = {
        "mean_NDCG_at_k": 0.80,
        "MRR": 0.85,
        "MAP": 0.75,
        "mean_precision_at_k": 0.40,
        "mean_recall_at_k": 0.80,
    }

    # Pass: Current metrics are identical or higher
    passed, reasons = gate.check_regression(baseline, baseline)
    assert passed is True
    assert len(reasons) == 0

    # Pass: Small drop within 3% (e.g. 1% drop: 0.80 -> 0.795)
    minor_drop = dict(baseline)
    minor_drop["mean_NDCG_at_k"] = 0.795
    passed, reasons = gate.check_regression(minor_drop, baseline)
    assert passed is True

    # Fail: Drop > 3% (e.g. 5% drop: 0.80 -> 0.75)
    severe_drop = dict(baseline)
    severe_drop["mean_NDCG_at_k"] = 0.75
    passed, reasons = gate.check_regression(severe_drop, baseline)
    assert passed is False
    assert len(reasons) == 1
    assert "NDCG@10" in reasons[0]


def test_baseline_save_and_load():
    with tempfile.TemporaryDirectory() as tmpdir:
        baseline_file = os.path.join(tmpdir, "test_baseline.json")
        gate = IRRegressionGate(baseline_path=baseline_file)

        metrics = {
            "mean_NDCG_at_k": 0.82,
            "MRR": 0.88,
            "MAP": 0.77,
        }
        gate.save_baseline(metrics, commit_hash="test1234")

        loaded = gate.load_baseline()
        assert loaded["commit_hash"] == "test1234"
        assert loaded["metrics"]["mean_NDCG_at_k"] == 0.82
        assert "sha256" in loaded


def test_run_gate_with_mock_search():
    with tempfile.TemporaryDirectory() as tmpdir:
        baseline_file = os.path.join(tmpdir, "test_baseline.json")
        queries = [
            EvaluationQuery(
                query_id="Q_TEST",
                query_text="zero trust",
                category="test",
                relevant_doc_ids=["D1", "D2"],
                graded_relevance={"D1": 3.0, "D2": 2.0},
            )
        ]
        gate = IRRegressionGate(
            baseline_path=baseline_file, queries=queries, top_k=5, threshold_drop=0.03
        )

        def mock_perfect_search(q: str, k: int):
            return ["D1", "D2"]

        # Initial run updates baseline
        code = gate.run_gate(search_fn=mock_perfect_search, update_baseline=True)
        assert code == 0

        # Next run passes
        code = gate.run_gate(search_fn=mock_perfect_search, update_baseline=False)
        assert code == 0

        # Degraded search fails gate
        def mock_degraded_search(q: str, k: int):
            return ["D_IRRELEVANT_1", "D_IRRELEVANT_2"]

        code = gate.run_gate(search_fn=mock_degraded_search, update_baseline=False)
        assert code == 1
