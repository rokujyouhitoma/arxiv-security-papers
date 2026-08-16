#!/usr/bin/env python3
"""
RAPTOR Hierarchical Summary Tree Index for Macro-Trend Queries.
"""

from collections import defaultdict
from typing import Any, Dict, List


class RAPTORTreeIndex:
    """
    RAPTOR Hierarchical Summary Tree Index for Macro-Trend Queries.
    """

    def __init__(self) -> None:
        self.clusters: List[Dict[str, Any]] = []

    def build_summary_tree(self, documents: List[Dict[str, Any]]) -> None:
        domain_groups: Dict[str, List[str]] = defaultdict(list)
        for doc in documents:
            for kw in doc.get("annotated_keywords", ["その他セキュリティ"]):
                domain_groups[kw].append(doc["id"])

        self.clusters = []
        for domain, doc_ids in domain_groups.items():
            self.clusters.append(
                {
                    "cluster_id": f"cluster-{len(self.clusters) + 1}",
                    "level": 1,
                    "domain": domain,
                    "summary": f"{domain} に関する最新セキュリティ研究・攻撃防御動向 ({len(doc_ids)} 件)",
                    "doc_ids": doc_ids[:50],
                }
            )

    def search_clusters(
        self, query_tokens: List[str], top_k: int = 3
    ) -> List[Dict[str, Any]]:
        results: List[Dict[str, Any]] = []
        for cluster in self.clusters:
            match_count = sum(
                1
                for qt in query_tokens
                if qt in cluster["domain"].lower() or qt in cluster["summary"].lower()
            )
            if match_count > 0:
                results.append({"cluster": cluster, "score": int(match_count)})

        results.sort(key=lambda x: int(x["score"]), reverse=True)
        return [dict(r["cluster"]) for r in results[:top_k]]
