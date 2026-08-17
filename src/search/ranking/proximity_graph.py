#!/usr/bin/env python3
"""
Paper Proximity Graph & Topology Engine for arXiv Security Papers.
Precomputes multi-dimensional paper-to-paper distances (TF-IDF Cosine, Security Feature Jaccard, Citation Co-occurrence)
and maintains a k-NN topological network for instant recommendations and Connected Papers style visualizations.
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

    def compute_similarity(self, doc_a: Dict[str, Any], doc_b: Dict[str, Any]) -> float:
        """
        Computes composite similarity between two papers:
        S(a, b) = 0.50 * CosineSim(tokens) + 0.35 * Jaccard(keywords) + 0.15 * CategoryMatch
        """
        # 1. Token Overlap / Cosine Sim Approximation (using precomputed norm if present)
        counts_a = doc_a.get("token_counts", {})
        counts_b = doc_b.get("token_counts", {})
        shared_tokens = set(counts_a.keys()) & set(counts_b.keys())
        if not shared_tokens:
            token_sim = 0.0
        else:
            dot_product = sum(counts_a[t] * counts_b[t] for t in shared_tokens)
            norm_a = doc_a.get("_norm") or (
                sum(v * v for v in counts_a.values()) ** 0.5
            )
            norm_b = doc_b.get("_norm") or (
                sum(v * v for v in counts_b.values()) ** 0.5
            )
            token_sim = (
                (dot_product / (norm_a * norm_b)) if norm_a > 0 and norm_b > 0 else 0.0
            )

        # 2. Security Keywords Jaccard Similarity
        kw_a = doc_a.get("_kw_set") or set(doc_a.get("annotated_keywords", []))
        kw_b = doc_b.get("_kw_set") or set(doc_b.get("annotated_keywords", []))
        shared_kw = kw_a & kw_b
        union_kw = kw_a | kw_b
        kw_sim = (len(shared_kw) / len(union_kw)) if union_kw else 0.0

        # 3. Category & Tag Overlap
        tags_a = doc_a.get("_tags_set") or set(t.lower() for t in doc_a.get("tags", []))
        tags_b = doc_b.get("_tags_set") or set(t.lower() for t in doc_b.get("tags", []))
        shared_tags = tags_a & tags_b
        cat_sim = 1.0 if shared_tags else 0.0

        return 0.50 * token_sim + 0.35 * kw_sim + 0.15 * cat_sim

    def build_graph(
        self,
        documents: List[Dict[str, Any]],
        inverted_keywords: Optional[Dict[str, List[str]]] = None,
    ) -> None:
        """
        Builds the k-NN proximity graph using inverted keywords and precomputed document vectors.
        """
        self.graph.clear()
        doc_map = {d["id"]: d for d in documents}

        # Precompute norms and sets once per document
        for doc in documents:
            counts = doc.get("token_counts", {})
            doc["_norm"] = sum(v * v for v in counts.values()) ** 0.5 if counts else 1.0
            doc["_kw_set"] = set(doc.get("annotated_keywords", []))
            doc["_tags_set"] = set(t.lower() for t in doc.get("tags", []))

        for doc in documents:
            doc_id = doc["id"]
            kw_list = doc.get("annotated_keywords", [])

            # Fast candidate pruning: papers sharing keywords
            candidate_ids: Set[str] = set()
            if inverted_keywords:
                for kw in kw_list:
                    candidate_ids.update(inverted_keywords.get(kw.lower(), []))
            else:
                candidate_ids = set(doc_map.keys())

            candidate_ids.discard(doc_id)
            if not candidate_ids:
                continue

            # Limit evaluation candidates to top 50 for O(N) performance scalability
            eval_candidates = (
                list(candidate_ids)[:50]
                if len(candidate_ids) > 50
                else list(candidate_ids)
            )

            scored_neighbors = []
            for target_id in eval_candidates:
                if target_id not in doc_map:
                    continue
                target_doc = doc_map[target_id]
                sim = self.compute_similarity(doc, target_doc)
                if sim > 0.05:
                    shared_kw = list(doc["_kw_set"] & target_doc["_kw_set"])
                    scored_neighbors.append(
                        {
                            "target_id": target_id,
                            "title": target_doc.get("title", ""),
                            "description": target_doc.get("description", ""),
                            "similarity": round(sim, 4),
                            "shared_keywords": shared_kw,
                            "path": target_doc.get("path", ""),
                            "published_date": target_doc.get("published_date", ""),
                        }
                    )

            scored_neighbors.sort(key=lambda x: x["similarity"], reverse=True)
            self.graph[doc_id] = scored_neighbors[: self.top_k_neighbors]

    def get_neighbors(self, doc_id: str) -> List[Dict[str, Any]]:
        """Returns precomputed nearest neighbors for a paper."""
        return self.graph.get(doc_id, [])

    def generate_mermaid_graph(self, doc_id: str, doc_title: str = "") -> str:
        """
        Generates a Connected Papers style Mermaid diagram string for visualization.
        """
        neighbors = self.get_neighbors(doc_id)
        if not neighbors:
            return ""

        clean_title = re.sub(r'["\'\(\)\[\]]', "", doc_title or doc_id)
        if len(clean_title) > 40:
            clean_title = clean_title[:37] + "..."

        lines = ["flowchart TD"]
        lines.append(f'    Current["📌 [閲覧中] {doc_id}<br/>{clean_title}"]')
        lines.append("    style Current fill:#4f46e5,stroke:#818cf8,color:#fff")

        for i, n in enumerate(neighbors, 1):
            n_id = n["target_id"]
            n_title = re.sub(r'["\'\(\)\[\]]', "", n.get("title", n_id))
            if len(n_title) > 35:
                n_title = n_title[:32] + "..."

            node_var = f"N{i}"
            kw_str = ", ".join(n.get("shared_keywords", [])[:2]) or "類似アプローチ"
            sim_pct = int(n.get("similarity", 0) * 100)

            lines.append(
                f'    {node_var}["📄 {n_id}<br/>{n_title}<br/><b>類似度 {sim_pct}%</b>"]'
            )
            lines.append(f'    Current ===|"{kw_str} ({sim_pct}%)"| {node_var}')

        return "\n".join(lines)
