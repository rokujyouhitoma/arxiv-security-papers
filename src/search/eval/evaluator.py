#!/usr/bin/env python3
"""
Search Engine Evaluator & Benchmarking Harness.
Executes evaluation datasets against search engines and generates comprehensive IR metric reports.
"""

from typing import Any, Callable, Dict, List, Optional, Sequence

from .dataset import DEFAULT_SECURITY_GOLD_STANDARD, EvaluationQuery
from .metrics import (
    compute_average_precision,
    compute_f1_score,
    compute_ndcg_at_k,
    compute_precision_at_k,
    compute_recall_at_k,
    compute_reciprocal_rank,
)


class SearchEvaluator:
    """Evaluates search engine ranking accuracy against ground-truth datasets."""

    def __init__(
        self,
        queries: Optional[List[EvaluationQuery]] = None,
        top_k: int = 5,
    ) -> None:
        self.queries = queries or DEFAULT_SECURITY_GOLD_STANDARD
        self.top_k = top_k

    def evaluate(
        self,
        search_fn: Callable[[str, int], Sequence[str]],
    ) -> Dict[str, Any]:
        """
        Executes all evaluation queries using `search_fn(query_text, top_k) -> List[doc_id]`
        and returns aggregated IR metrics.
        """
        query_results: List[Dict[str, Any]] = []
        total_ap = 0.0
        total_rr = 0.0
        total_ndcg = 0.0
        total_p = 0.0
        total_r = 0.0
        total_f1 = 0.0

        for eq in self.queries:
            retrieved_ids = list(search_fn(eq.query_text, self.top_k))

            p_at_k = compute_precision_at_k(
                retrieved_ids, eq.relevant_doc_ids, k=self.top_k
            )
            r_at_k = compute_recall_at_k(
                retrieved_ids, eq.relevant_doc_ids, k=self.top_k
            )
            f1 = compute_f1_score(p_at_k, r_at_k)
            ap = compute_average_precision(retrieved_ids, eq.relevant_doc_ids)
            rr = compute_reciprocal_rank(retrieved_ids, eq.relevant_doc_ids)
            ndcg = compute_ndcg_at_k(retrieved_ids, eq.graded_relevance, k=self.top_k)

            total_p += p_at_k
            total_r += r_at_k
            total_f1 += f1
            total_ap += ap
            total_rr += rr
            total_ndcg += ndcg

            query_results.append(
                {
                    "query_id": eq.query_id,
                    "query_text": eq.query_text,
                    "category": eq.category,
                    "retrieved_ids": retrieved_ids,
                    "relevant_ids": eq.relevant_doc_ids,
                    "precision_at_k": round(p_at_k, 4),
                    "recall_at_k": round(r_at_k, 4),
                    "f1_score": round(f1, 4),
                    "average_precision": round(ap, 4),
                    "reciprocal_rank": round(rr, 4),
                    "ndcg_at_k": round(ndcg, 4),
                }
            )

        n = len(self.queries)
        summary = {
            "num_queries": n,
            "top_k": self.top_k,
            "mean_precision_at_k": round(total_p / n, 4) if n > 0 else 0.0,
            "mean_recall_at_k": round(total_r / n, 4) if n > 0 else 0.0,
            "mean_f1_score": round(total_f1 / n, 4) if n > 0 else 0.0,
            "MAP": round(total_ap / n, 4) if n > 0 else 0.0,
            "MRR": round(total_rr / n, 4) if n > 0 else 0.0,
            "mean_NDCG_at_k": round(total_ndcg / n, 4) if n > 0 else 0.0,
        }

        return {
            "summary": summary,
            "query_details": query_results,
        }

    def generate_markdown_report(self, eval_result: Dict[str, Any]) -> str:
        """Generates a clean Markdown evaluation report with metric tables."""
        s = eval_result["summary"]
        details = eval_result["query_details"]

        lines = [
            "# 検索エンジン評価レポート (IR Quality Benchmark Report)",
            "",
            f"## 1. 総合評価サマリー (Overall Metrics at K={s['top_k']})",
            "",
            "| 評価指標 (Metric) | スコア (Score) | 理想値 (Ideal) | 説明 (Description) |",
            "| :--- | :---: | :---: | :--- |",
            f"| **MAP (Mean Average Precision)** | **{s['MAP']}** | 1.0000 | 複数クエリ全体の平均適合率（ランキング順位重み付き） |",
            f"| **MRR (Mean Reciprocal Rank)** | **{s['MRR']}** | 1.0000 | 最初の正解文書が出現した順位の逆数平均 |",
            f"| **Mean NDCG@{s['top_k']}** | **{s['mean_NDCG_at_k']}** | 1.0000 | 多段階関連度を考慮した正規化割引累積利得 |",
            f"| **Mean Precision@{s['top_k']} (適合率)** | **{s['mean_precision_at_k']}** | 1.0000 | "
            f"上位 {s['top_k']} 件中、正解文書が含まれる割合 |",
            f"| **Mean Recall@{s['top_k']} (再現率)** | **{s['mean_recall_at_k']}** | 1.0000 | "
            f"全正解文書中、上位 {s['top_k']} 件に取得できた割合 |",
            f"| **Mean F1-Score (F値)** | **{s['mean_f1_score']}** | 1.0000 | 適合率と再現率の調和平均 |",
            "",
            "---",
            "",
            "## 2. クエリ別詳細結果 (Query Breakdown)",
            "",
            f"| Query ID | カテゴリ | クエリ文字列 | P@{s['top_k']} | R@{s['top_k']} | F1 | AP | RR | NDCG@{s['top_k']} |",
            "| :---: | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |",
        ]

        for q in details:
            lines.append(
                f"| {q['query_id']} | `{q['category']}` | {q['query_text']} | {q['precision_at_k']} | "
                f"{q['recall_at_k']} | {q['f1_score']} | {q['average_precision']} | {q['reciprocal_rank']} | "
                f"{q['ndcg_at_k']} |"
            )

        return "\n".join(lines) + "\n"
