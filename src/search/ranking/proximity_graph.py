#!/usr/bin/env python3
"""
Document Proximity Graph & Topology Engine.
Precomputes multi-dimensional document-to-document distances (TF-IDF Cosine, Feature Jaccard, Co-occurrence)
and maintains a k-NN topological network for instant recommendations and Graph visualizations.
"""

import re
from collections import defaultdict
from typing import Any, Dict, List, Optional, Set


class ProximityGraphIndex:
    """
    k-NN Paper Proximity Graph Index.
    """

    def __init__(self, top_k_neighbors: int = 6) -> None:
        self.top_k_neighbors = top_k_neighbors
        self.graph: Dict[str, List[Dict[str, Any]]] = defaultdict(list)

    def _get_doc_norm(self, doc: Dict[str, Any], counts: Dict[str, int]) -> float:
        norm = doc.get("_norm")
        if norm is not None:
            return float(norm)
        return (sum(v * v for v in counts.values()) ** 0.5) if counts else 0.0

    def _compute_token_sim(self, doc_a: Dict[str, Any], doc_b: Dict[str, Any]) -> float:
        counts_a = doc_a.get("token_counts", {})
        counts_b = doc_b.get("token_counts", {})
        shared = set(counts_a.keys()) & set(counts_b.keys())
        if not shared:
            return 0.0
        dot_product = sum(counts_a[t] * counts_b[t] for t in shared)
        norm_a = self._get_doc_norm(doc_a, counts_a)
        norm_b = self._get_doc_norm(doc_b, counts_b)
        return (dot_product / (norm_a * norm_b)) if norm_a > 0 and norm_b > 0 else 0.0

    def _get_tags_set(self, doc: Dict[str, Any]) -> Set[str]:
        tags = doc.get("_tags_set")
        if tags is not None:
            return tags
        return {str(t).lower() for t in doc.get("tags", [])}

    def _get_kw_set(self, doc: Dict[str, Any]) -> Set[str]:
        kw = doc.get("_kw_set")
        if kw is not None:
            return kw
        return set(doc.get("annotated_keywords", []))

    def _calc_kw_sim(self, doc_a: Dict[str, Any], doc_b: Dict[str, Any]) -> float:
        kw_a = self._get_kw_set(doc_a)
        kw_b = self._get_kw_set(doc_b)
        union_kw = kw_a | kw_b
        return (len(kw_a & kw_b) / len(union_kw)) if union_kw else 0.0

    def _calc_cat_sim(self, doc_a: Dict[str, Any], doc_b: Dict[str, Any]) -> float:
        tags_a = self._get_tags_set(doc_a)
        tags_b = self._get_tags_set(doc_b)
        return 1.0 if (tags_a & tags_b) else 0.0

    def compute_similarity(self, doc_a: Dict[str, Any], doc_b: Dict[str, Any]) -> float:
        """Computes composite similarity between two papers."""
        token_sim = self._compute_token_sim(doc_a, doc_b)
        kw_sim = self._calc_kw_sim(doc_a, doc_b)
        cat_sim = self._calc_cat_sim(doc_a, doc_b)
        return 0.50 * token_sim + 0.35 * kw_sim + 0.15 * cat_sim

    def _score_single_neighbor(
        self, doc: Dict[str, Any], target_id: str, doc_map: Dict[str, Dict[str, Any]]
    ) -> Optional[Dict[str, Any]]:
        target_doc = doc_map.get(target_id)
        if not target_doc:
            return None
        sim = self.compute_similarity(doc, target_doc)
        if sim <= 0.05:
            return None
        return {
            "target_id": target_id,
            "title": target_doc.get("title", ""),
            "description": target_doc.get("description", ""),
            "similarity": round(sim, 4),
            "shared_keywords": list(doc["_kw_set"] & target_doc["_kw_set"]),
            "path": target_doc.get("path", ""),
            "published_date": target_doc.get("published_date", ""),
        }

    def _find_scored_neighbors(
        self,
        doc: Dict[str, Any],
        candidate_ids: List[str],
        doc_map: Dict[str, Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        scored = [
            cand
            for target_id in candidate_ids
            if (cand := self._score_single_neighbor(doc, target_id, doc_map))
            is not None
        ]
        scored.sort(key=lambda x: x["similarity"], reverse=True)
        return scored[: self.top_k_neighbors]

    def _preprocess_documents(self, documents: List[Dict[str, Any]]) -> None:
        for doc in documents:
            counts = doc.get("token_counts", {})
            doc["_norm"] = sum(v * v for v in counts.values()) ** 0.5 if counts else 1.0
            doc["_kw_set"] = set(doc.get("annotated_keywords", []))
            doc["_tags_set"] = set(t.lower() for t in doc.get("tags", []))

    def _collect_candidate_ids(
        self,
        doc: Dict[str, Any],
        inverted_keywords: Optional[Dict[str, List[str]]],
        doc_map: Dict[str, Dict[str, Any]],
    ) -> Set[str]:
        if not inverted_keywords:
            return set(doc_map.keys())
        candidate_ids: Set[str] = set()
        for kw in doc.get("annotated_keywords", []):
            candidate_ids.update(inverted_keywords.get(kw.lower(), []))
        return candidate_ids

    def build_graph(
        self,
        documents: List[Dict[str, Any]],
        inverted_keywords: Optional[Dict[str, List[str]]] = None,
    ) -> None:
        """Builds the k-NN proximity graph using inverted keywords and precomputed document vectors."""
        self.graph.clear()
        doc_map = {d["id"]: d for d in documents}
        self._preprocess_documents(documents)

        for doc in documents:
            doc_id = doc["id"]
            candidates = self._collect_candidate_ids(doc, inverted_keywords, doc_map)
            candidates.discard(doc_id)
            if candidates:
                self.graph[doc_id] = self._find_scored_neighbors(
                    doc, list(candidates)[:50], doc_map
                )

    def get_neighbors(self, doc_id: str) -> List[Dict[str, Any]]:
        """Returns precomputed nearest neighbors for a paper."""
        return self.graph.get(doc_id, [])

    def _format_mermaid_title(self, raw_title: str, max_len: int) -> str:
        clean = re.sub(r'["\'\(\)\[\]]', "", raw_title)
        if len(clean) > max_len:
            return clean[: max_len - 3] + "..."
        return clean

    def _render_neighbor_node(self, idx: int, n: Dict[str, Any]) -> tuple[str, str]:
        n_id = n["target_id"]
        n_title = self._format_mermaid_title(n.get("title", n_id), 35)
        node_var = f"N{idx}"
        kw_str = ", ".join(n.get("shared_keywords", [])[:2]) or "類似アプローチ"
        sim_pct = int(n.get("similarity", 0) * 100)
        node_line = (
            f'    {node_var}["📄 {n_id}<br/>{n_title}<br/><b>類似度 {sim_pct}%</b>"]'
        )
        edge_line = f'    Current ===|"{kw_str} ({sim_pct}%)"| {node_var}'
        return node_line, edge_line

    def generate_mermaid_graph(self, doc_id: str, doc_title: str = "") -> str:
        """
        Generates a Connected Papers style Mermaid diagram string for visualization.
        """
        neighbors = self.get_neighbors(doc_id)
        if not neighbors:
            return ""

        clean_title = self._format_mermaid_title(doc_title or doc_id, 40)
        lines = [
            "flowchart TD",
            f'    Current["📌 [閲覧中] {doc_id}<br/>{clean_title}"]',
            "    style Current fill:#4f46e5,stroke:#818cf8,color:#fff",
        ]

        for i, n in enumerate(neighbors, 1):
            n_line, e_line = self._render_neighbor_node(i, n)
            lines.append(n_line)
            lines.append(e_line)

        return "\n".join(lines)
