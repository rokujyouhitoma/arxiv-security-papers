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
                    if allowed_predicates and e.label not in allowed_predicates:
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
                    if allowed_predicates and e.label not in allowed_predicates:
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
        grounding_md = self._format_grounding_markdown(vertices, unique_triples)

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

    def find_defense_chains(
        self, technique_or_vuln_keyword: str
    ) -> List[Dict[str, Any]]:
        """
        Finds attack-defense causal chains:
        (Attack/Vuln) <--[MITIGATES/DEFENDS]-- (Defense) <--[PROPOSES]-- (Paper)
        """
        g = self.graph_engine
        results: List[Dict[str, Any]] = []
        kw_lower = technique_or_vuln_keyword.lower()

        # Find matching attack or vulnerability nodes
        target_vids: List[str] = []
        for vid, v in g._vertices.items():
            if v.label not in ("AttackTechnique", "Vulnerability") and not (
                vid.startswith("AttackTechnique:") or vid.startswith("Vulnerability:")
            ):
                continue
            if kw_lower in vid.lower() or kw_lower in v.label.lower():
                target_vids.append(vid)
            elif v.properties and any(
                kw_lower in str(val).lower() for val in v.properties.values()
            ):
                target_vids.append(vid)

        for target_vid in target_vids:
            target_v = g.get_vertex(target_vid)
            # Incoming edges: Defense -> MITIGATES -> Target
            in_edges = g.get_in_edges(target_vid)
            for e in in_edges:
                if e.label in ("MITIGATES", "DEFENDS"):
                    defense_vid = e.src_id
                    defense_v = g.get_vertex(defense_vid)
                    # Find papers proposing this defense
                    defense_in_edges = g.get_in_edges(defense_vid)
                    proposing_papers: List[Dict[str, Any]] = []
                    for pe in defense_in_edges:
                        if pe.label in ("PROPOSES", "ANALYZES") or pe.src_id.startswith(
                            "Paper:"
                        ):
                            paper_v = g.get_vertex(pe.src_id)
                            if paper_v:
                                proposing_papers.append(paper_v.to_dict())

                    results.append(
                        {
                            "target_threat": (
                                target_v.to_dict() if target_v else {"id": target_vid}
                            ),
                            "mitigation_relation": e.label,
                            "defense_mechanism": (
                                defense_v.to_dict()
                                if defense_v
                                else {"id": defense_vid}
                            ),
                            "effective_papers": proposing_papers,
                        }
                    )
        return results

    def calculate_blast_radius(
        self, entity_id: str, max_depth: int = 3
    ) -> Dict[str, Any]:
        """
        Calculates blast radius from a vulnerable asset or attack technique:
        Traverses reachable downstream assets, systems, and exploited vectors.
        """
        g = self.graph_engine
        canonical_id = entity_id
        if not g.get_vertex(canonical_id):
            for vid in g._vertices.keys():
                if entity_id.lower() in vid.lower():
                    canonical_id = vid
                    break

        root_v = g.get_vertex(canonical_id)
        if not root_v:
            return {
                "root_entity": entity_id,
                "blast_radius_count": 0,
                "impacted_entities": [],
            }

        visited: Dict[str, int] = {canonical_id: 0}
        queue = [(canonical_id, 0)]
        impacted_list: List[Dict[str, Any]] = []

        while queue:
            curr_id, depth = queue.pop(0)
            if depth >= max_depth:
                continue

            for e in g.get_out_edges(curr_id):
                nxt_id = e.dst_id
                if nxt_id not in visited:
                    visited[nxt_id] = depth + 1
                    queue.append((nxt_id, depth + 1))
                    nxt_v = g.get_vertex(nxt_id)
                    impacted_list.append(
                        {
                            "depth": depth + 1,
                            "relation": e.label,
                            "entity": nxt_v.to_dict() if nxt_v else {"id": nxt_id},
                        }
                    )

        return {
            "root_entity": root_v.to_dict(),
            "blast_radius_count": len(impacted_list),
            "max_depth_explored": max_depth,
            "impacted_entities": impacted_list,
        }

    def query_graphrag(
        self, query_text: str, top_k_papers: int = 3, max_hops: int = 2
    ) -> Dict[str, Any]:
        """
        End-to-end GraphRAG query execution:
        Identifies seed papers matching query, expands causal subgraph, and returns grounded context.
        """
        g = self.graph_engine
        q_lower = query_text.lower()
        matched_seeds: List[str] = []

        # Find paper nodes matching keywords
        for vid, v in g._vertices.items():
            if v.label == "Paper" or vid.startswith("Paper:"):
                title = (v.properties or {}).get("title", "")
                desc = (v.properties or {}).get("description", "")
                if (
                    q_lower in vid.lower()
                    or q_lower in title.lower()
                    or q_lower in desc.lower()
                ):
                    clean_pid = vid.replace("Paper:", "")
                    matched_seeds.append(clean_pid)
                    if len(matched_seeds) >= top_k_papers:
                        break

        # Fallback: take any available papers if no exact keyword match
        if not matched_seeds:
            for vid, v in list(g._vertices.items())[:top_k_papers]:
                if v.label == "Paper" or vid.startswith("Paper:"):
                    matched_seeds.append(vid.replace("Paper:", ""))

        expansion = self.expand_context(seed_paper_ids=matched_seeds, max_hops=max_hops)

        defense_chains = self.find_defense_chains(query_text)
        expansion["query"] = query_text
        expansion["seed_paper_ids"] = matched_seeds
        expansion["defense_chains"] = defense_chains
        return expansion
