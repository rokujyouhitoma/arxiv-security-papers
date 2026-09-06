#!/usr/bin/env python3
"""
Unit and regression tests for SOTA IR Benchmark Runner (Issue 193).
Tests CTI-Bench dataset generation, performance profiling, multi-paradigm benchmark execution,
and Markdown comparison report generation.
"""

import os
import sys
import unittest

if "src" not in sys.path:
    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "src")
        ),
    )

from search.eval.dataset import BEIRDataset, generate_cti_bench_dataset
from search.eval.metrics import PerformanceMetrics, profile_search_performance
from search.eval.sota_runner import SOTABenchmarkRunner


class TestSOTABenchmarkRunner(unittest.TestCase):
    """Tests SOTA IR Benchmark runner and comparative evaluation metrics."""

    def test_cti_bench_dataset_generation(self) -> None:
        """Verifies deterministic generation of CTI-Bench dataset with corpus, queries, and qrels."""
        dataset = generate_cti_bench_dataset(num_docs=30, num_queries=5)
        self.assertIsInstance(dataset, BEIRDataset)
        self.assertEqual(len(dataset.corpus), 30)
        self.assertEqual(len(dataset.queries), 5)
        self.assertEqual(len(dataset.qrels), 5)

        # Check document structure
        doc_0 = dataset.corpus["cti-zero-trust-0000"]
        self.assertIn("title", doc_0)
        self.assertIn("text", doc_0)
        self.assertIn("tags", doc_0)

        # Check conversion to EvaluationQuery
        eval_queries = dataset.to_evaluation_queries()
        self.assertEqual(len(eval_queries), 5)
        self.assertTrue(len(eval_queries[0].relevant_doc_ids) > 0)

    def test_profile_search_performance(self) -> None:
        """Verifies latency, throughput (QPS), and memory profiling harness."""

        def mock_search(query: str, top_k: int) -> list[str]:
            return [f"doc-{i}" for i in range(top_k)]

        perf = profile_search_performance(
            search_fn=mock_search,
            queries=["query 1", "query 2"],
            top_k=5,
            warmup=1,
            iterations=2,
        )
        self.assertIsInstance(perf, PerformanceMetrics)
        self.assertGreater(perf.qps, 0.0)
        self.assertGreaterEqual(perf.latency_p50_ms, 0.0)
        self.assertGreaterEqual(perf.memory_rss_mb, 0.0)
        d = perf.to_dict()
        self.assertIn("qps", d)
        self.assertIn("latency_p95_ms", d)

    def test_end_to_end_sota_benchmark_execution(self) -> None:
        """Verifies end-to-end benchmark run across BM25, Vector, and Hybrid paradigms."""
        dataset = generate_cti_bench_dataset(num_docs=24, num_queries=4)
        runner = SOTABenchmarkRunner(dataset=dataset, top_k=5)
        results = runner.run_benchmark()

        self.assertIn("benchmark_name", results)
        self.assertIn("models", results)
        models = results["models"]
        self.assertIn("BM25 (Lucene Baseline)", models)
        self.assertIn("Dense Vector (Chroma/Qdrant Baseline)", models)
        self.assertIn("Hybrid SOTA (BM25 + HNSW + Graph)", models)

        for m_name, m_data in models.items():
            ir = m_data["ir_metrics"]
            perf = m_data["performance_metrics"]
            self.assertIn("mean_NDCG_at_k", ir)
            self.assertIn("mean_recall_at_k", ir)
            self.assertIn("qps", perf)
            self.assertGreater(perf["qps"], 0.0)

        # Markdown report generation
        md = runner.format_markdown_report(results)
        self.assertIn("# SOTA 情報検索（IR）客観的性能評価レポート", md)
        self.assertIn("BM25 (Lucene Baseline)", md)
        self.assertIn("Hybrid SOTA (BM25 + HNSW + Graph)", md)
        self.assertIn("## 3. 結論（車輪の再発明に対する工学的回答）", md)


if __name__ == "__main__":
    unittest.main()
