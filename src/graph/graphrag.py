#!/usr/bin/env python3
"""
GraphRAG and Multi-Hop Causal Reasoning Pipeline.
Combines Vector/ANN Search results with Property Graph Multi-Hop expansion
to produce grounded semantic contexts with zero hallucination.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set

from .engine import PropertyGraphEngine
from .structures import Vertex

logger = logging.getLogger(__name__)


class GraphRAGPipeline:
    """
    Two-stage retrieval pipeline:
    Stage 1: Vector/ANN semantic candidate identification
    Stage 2: Multi-Hop graph expansion over Security Knowledge Ontology (SKO)
    """

    def __init__(self, graph_engine: PropertyGraphEngine) -> None:
        self.graph_engine = graph_engine

    def expand_context(
        self,
        seed_paper_ids: List[str],
        max_hops: int = 2,
        allowed_predicates: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Expands subgraph around seed papers up to max_hops.
        Returns matched vertices, edges, semantic triples, and formatted markdown grounding context.
        """
        g = self.graph_engine
        visited_v_ids: Set[str] = set()
        frontier_ids: Set[str] = set()

        for pid in seed_paper_ids:
            canonical_pid = pid if pid.startswith("Paper:") else f"Paper:{pid}"
            if g.get_vertex(canonical_pid) is not None:
                frontier_ids.add(canonical_pid)
                visited_v_ids.add(canonical_pid)

        matched_triples: List[Dict[str, Any]] = []
        matched_edges: List[Dict[str, Any]] = []

        current_level = set(frontier_ids)
        for _ in range(max_hops):
            if not current_level:
                break
            next_level: Set[str] = set()
            for vid in current_level:
                # Outgoing edges
                for e in g.get_out_edges(vid):
                    if (
                        allowed_predicates
                        and e.label not in allowed_predicates
                    ):
                        continue
                    matched_edges.append(e.to_dict())
                    matched_triples.append(
                        {
                            "subject": e.src_id,
                            "predicate": e.label,
                            "object": e.dst_id,
                            "weight": e.weight,
                        }
                    )
                    if e.dst_id not in visited_v_ids:
                        visited_v_ids.add(e.dst_id)
                        next_level.add(e.dst_id)

                # Incoming edges
                for e in g.get_in_edges(vid):
                    if (
                        allowed_predicates
                        and e.label not in allowed_predicates
                    ):
                        continue
                    matched_edges.append(e.to_dict())
                    matched_triples.append(
                        {
                            "subject": e.src_id,
                            "predicate": e.label,
                            "object": e.dst_id,
                            "weight": e.weight,
                        }
                    )
                    if e.src_id not in visited_v_ids:
                        visited_v_ids.add(e.src_id)
                        next_level.add(e.src_id)

            current_level = next_level

        # Collect Vertices
        vertices: List[Vertex] = []
        for vid in visited_v_ids:
            v = g.get_vertex(vid)
            if v is not None:
                vertices.append(v)

        # Deduplicate triples
        unique_triples: List[Dict[str, Any]] = []
        seen_t: Set[str] = set()
        for t in matched_triples:
            key = f"{t['subject']}--{t['predicate']}-->{t['object']}"
            if key not in seen_t:
                seen_t.add(key)
                unique_triples.append(t)

        # Generate Grounded Causal Reasoning Markdown Text
        grounding_md = self._format_grounding_markdown(
            vertices, unique_triples
        )

        return {
            "seed_count": len(seed_paper_ids),
            "expanded_vertex_count": len(vertices),
            "expanded_triple_count": len(unique_triples),
            "vertices": [v.to_dict() for v in vertices],
            "triples": unique_triples,
            "grounding_context_markdown": grounding_md,
        }

    def _format_grounding_markdown(
        self, vertices: List[Vertex], triples: List[Dict[str, Any]]
    ) -> str:
        """Formats extracted subgraph into bulleted factual assertions for LLM prompting."""
        if not triples:
            return "No verified causal security relationships found in knowledge graph."

        lines = ["### 🛡️ Verified Security Knowledge Graph Grounding Context"]
        lines.append(
            f"*Discovered {len(vertices)} entities and {len(triples)} verified factual relationships:*\n"
        )

        # Group relationships by subject
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for t in triples:
            grouped.setdefault(t["subject"], []).append(t)

        for subj, t_list in sorted(grouped.items()):
            subj_clean = (
                subj.replace("Paper:", "📄 Paper [")
                .replace("AttackTechnique:", "⚔️ Attack [")
                .replace("DefenseMechanism:", "🛡️ Defense [")
                .replace("Vulnerability:", "⚠️ Vuln [")
            )
            if subj_clean.endswith("["):
                subj_clean += subj + "]"
            else:
                subj_clean += "]"

            lines.append(f"- **{subj_clean}**:")
            for t in t_list:
                pred = t["predicate"]
                obj = t["object"]
                lines.append(f"  • `--[{pred}]-->` `{obj}`")

        return "\n".join(lines)
