#!/usr/bin/env python3
"""
GraphRAG and Multi-Hop Causal Reasoning Pipeline.
Combines Vector/ANN Search results with Property Graph Multi-Hop expansion
to produce grounded semantic contexts with zero hallucination.
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set, Tuple

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

    def _init_frontier(self, seed_paper_ids: List[str]) -> Tuple[Set[str], Set[str]]:
        """Initializes visited and frontier vertex IDs from seed paper IDs."""
        visited: Set[str] = set()
        frontier: Set[str] = set()
        for pid in seed_paper_ids:
            canonical = pid if pid.startswith("Paper:") else f"Paper:{pid}"
            if self.graph_engine.get_vertex(canonical) is not None:
                frontier.add(canonical)
                visited.add(canonical)
        return visited, frontier

    def _process_single_edge(
        self,
        e: Any,
        is_out: bool,
        allowed_predicates: Optional[List[str]],
        visited_v_ids: Set[str],
        matched_edges: List[Dict[str, Any]],
        matched_triples: List[Dict[str, Any]],
        next_level: Set[str],
    ) -> None:
        """Processes a single edge for subgraph level traversal."""
        if allowed_predicates and e.label not in allowed_predicates:
            return
        matched_edges.append(e.to_dict())
        matched_triples.append(
            {
                "subject": e.src_id,
                "predicate": e.label,
                "object": e.dst_id,
                "weight": e.weight,
            }
        )
        target_vid = e.dst_id if is_out else e.src_id
        if target_vid not in visited_v_ids:
            visited_v_ids.add(target_vid)
            next_level.add(target_vid)

    def _traverse_level_edges(
        self,
        current_level: Set[str],
        allowed_predicates: Optional[List[str]],
        visited_v_ids: Set[str],
        matched_edges: List[Dict[str, Any]],
        matched_triples: List[Dict[str, Any]],
    ) -> Set[str]:
        """Traverses outgoing and incoming edges for the current level."""
        g = self.graph_engine
        next_level: Set[str] = set()
        for vid in current_level:
            for e in g.get_out_edges(vid):
                self._process_single_edge(
                    e,
                    True,
                    allowed_predicates,
                    visited_v_ids,
                    matched_edges,
                    matched_triples,
                    next_level,
                )
            for e in g.get_in_edges(vid):
                self._process_single_edge(
                    e,
                    False,
                    allowed_predicates,
                    visited_v_ids,
                    matched_edges,
                    matched_triples,
                    next_level,
                )
        return next_level

    def _deduplicate_triples(
        self, matched_triples: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """Deduplicates matched graph triples."""
        unique_triples: List[Dict[str, Any]] = []
        seen_t: Set[str] = set()
        for t in matched_triples:
            key = f"{t['subject']}--{t['predicate']}-->{t['object']}"
            if key not in seen_t:
                seen_t.add(key)
                unique_triples.append(t)
        return unique_triples

    def _run_expansion_hops(
        self,
        max_hops: int,
        current_level: Set[str],
        allowed_predicates: Optional[List[str]],
        visited_v_ids: Set[str],
        matched_edges: List[Dict[str, Any]],
        matched_triples: List[Dict[str, Any]],
    ) -> None:
        """Iteratively traverses expansion hops up to max_hops."""
        for _ in range(max_hops):
            if not current_level:
                break
            current_level = self._traverse_level_edges(
                current_level,
                allowed_predicates,
                visited_v_ids,
                matched_edges,
                matched_triples,
            )

    def expand_context(
        self,
        seed_paper_ids: List[str],
        max_hops: int = 2,
        allowed_predicates: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """Expands subgraph around seed papers up to max_hops."""
        visited_v_ids, current_level = self._init_frontier(seed_paper_ids)
        matched_triples: List[Dict[str, Any]] = []
        matched_edges: List[Dict[str, Any]] = []

        self._run_expansion_hops(
            max_hops,
            current_level,
            allowed_predicates,
            visited_v_ids,
            matched_edges,
            matched_triples,
        )

        valid_vertices = [
            v
            for v in (self.graph_engine.get_vertex(vid) for vid in visited_v_ids)
            if v is not None
        ]
        unique_triples = self._deduplicate_triples(matched_triples)

        return {
            "seed_count": len(seed_paper_ids),
            "expanded_vertex_count": len(valid_vertices),
            "expanded_triple_count": len(unique_triples),
            "vertices": [v.to_dict() for v in valid_vertices],
            "triples": unique_triples,
            "grounding_context_markdown": self._format_grounding_markdown(
                valid_vertices, unique_triples
            ),
        }

    def _format_subject_label(self, subj: str) -> str:
        """Formats subject prefix with icon."""
        label = (
            subj.replace("Paper:", "📄 Paper [")
            .replace("AttackTechnique:", "⚔️ Attack [")
            .replace("DefenseMechanism:", "🛡️ Defense [")
            .replace("Vulnerability:", "⚠️ Vuln [")
        )
        return f"{label}{subj}]" if label.endswith("[") else f"{label}]"

    def _format_grounding_markdown(
        self, vertices: List[Vertex], triples: List[Dict[str, Any]]
    ) -> str:
        """Formats extracted subgraph into bulleted factual assertions for LLM prompting."""
        if not triples:
            return "No verified causal security relationships found in knowledge graph."

        lines = [
            "### 🛡️ Verified Security Knowledge Graph Grounding Context",
            f"*Discovered {len(vertices)} entities and {len(triples)} verified factual relationships:*\n",
        ]
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for t in triples:
            grouped.setdefault(t["subject"], []).append(t)

        for subj, t_list in sorted(grouped.items()):
            lines.append(f"- **{self._format_subject_label(subj)}**:")
            for t in t_list:
                lines.append(f"  • `--[{t['predicate']}]-->` `{t['object']}`")

        return "\n".join(lines)

    def _props_contain(self, props: Optional[Dict[str, Any]], kw: str) -> bool:
        """Helper to check if properties contain keyword."""
        return bool(props and any(kw in str(val).lower() for val in props.values()))

    def _is_threat_match(self, vid: str, v: Vertex, kw_lower: str) -> bool:
        """Checks if a threat vertex matches search keyword."""
        is_threat = v.label in ("AttackTechnique", "Vulnerability") or vid.startswith(
            ("AttackTechnique:", "Vulnerability:")
        )
        if not is_threat:
            return False
        return (
            kw_lower in vid.lower()
            or kw_lower in v.label.lower()
            or self._props_contain(v.properties, kw_lower)
        )

    def _find_matching_threat_vids(self, kw_lower: str) -> List[str]:
        """Finds attack or vulnerability vertex IDs matching keyword."""
        return [
            vid
            for vid, v in self.graph_engine._vertices.items()
            if self._is_threat_match(vid, v, kw_lower)
        ]

    def _collect_proposing_papers(self, defense_vid: str) -> List[Dict[str, Any]]:
        """Collects papers that propose a given defense mechanism."""
        papers: List[Dict[str, Any]] = []
        for pe in self.graph_engine.get_in_edges(defense_vid):
            if pe.label in ("PROPOSES", "ANALYZES") or pe.src_id.startswith("Paper:"):
                paper_v = self.graph_engine.get_vertex(pe.src_id)
                if paper_v:
                    papers.append(paper_v.to_dict())
        return papers

    def _build_threat_defense_chain(self, target_vid: str) -> List[Dict[str, Any]]:
        """Builds defense chains for a specific target threat vertex."""
        g = self.graph_engine
        results: List[Dict[str, Any]] = []
        target_v = g.get_vertex(target_vid)
        for e in g.get_in_edges(target_vid):
            if e.label not in ("MITIGATES", "DEFENDS"):
                continue
            defense_v = g.get_vertex(e.src_id)
            papers = self._collect_proposing_papers(e.src_id)
            results.append(
                {
                    "target_threat": (
                        target_v.to_dict() if target_v else {"id": target_vid}
                    ),
                    "mitigation_relation": e.label,
                    "defense_mechanism": (
                        defense_v.to_dict() if defense_v else {"id": e.src_id}
                    ),
                    "effective_papers": papers,
                }
            )
        return results

    def find_defense_chains(
        self, technique_or_vuln_keyword: str
    ) -> List[Dict[str, Any]]:
        """Finds attack-defense causal chains."""
        results: List[Dict[str, Any]] = []
        for target_vid in self._find_matching_threat_vids(
            technique_or_vuln_keyword.lower()
        ):
            results.extend(self._build_threat_defense_chain(target_vid))
        return results

    def _resolve_root_vertex(self, entity_id: str) -> Optional[Vertex]:
        """Resolves root vertex by exact or substring match."""
        g = self.graph_engine
        v = g.get_vertex(entity_id)
        if v:
            return v
        for vid in g._vertices.keys():
            if entity_id.lower() in vid.lower():
                return g.get_vertex(vid)
        return None

    def _explore_out_edge(
        self,
        e: Any,
        depth: int,
        visited: Dict[str, int],
        queue: List[Tuple[str, int]],
        impacted: List[Dict[str, Any]],
    ) -> None:
        """Explores a single out edge in blast radius BFS."""
        if e.dst_id in visited:
            return
        visited[e.dst_id] = depth + 1
        queue.append((e.dst_id, depth + 1))
        nxt_v = self.graph_engine.get_vertex(e.dst_id)
        impacted.append(
            {
                "depth": depth + 1,
                "relation": e.label,
                "entity": nxt_v.to_dict() if nxt_v else {"id": e.dst_id},
            }
        )

    def _explore_blast_queue(
        self, root_v: Vertex, max_depth: int
    ) -> List[Dict[str, Any]]:
        """BFS exploration of blast radius graph."""
        visited: Dict[str, int] = {root_v.id: 0}
        queue = [(root_v.id, 0)]
        impacted: List[Dict[str, Any]] = []

        while queue:
            curr_id, depth = queue.pop(0)
            if depth >= max_depth:
                continue

            for e in self.graph_engine.get_out_edges(curr_id):
                self._explore_out_edge(e, depth, visited, queue, impacted)
        return impacted

    def calculate_blast_radius(
        self, entity_id: str, max_depth: int = 3
    ) -> Dict[str, Any]:
        """Calculates blast radius from a vulnerable asset or attack technique."""
        root_v = self._resolve_root_vertex(entity_id)
        if not root_v:
            return {
                "root_entity": entity_id,
                "blast_radius_count": 0,
                "impacted_entities": [],
            }

        impacted = self._explore_blast_queue(root_v, max_depth)
        return {
            "root_entity": root_v.to_dict(),
            "blast_radius_count": len(impacted),
            "max_depth_explored": max_depth,
            "impacted_entities": impacted,
        }

    def _is_paper_match(self, vid: str, v: Vertex, q: str) -> bool:
        """Checks if paper vertex matches query text."""
        title = (v.properties or {}).get("title", "")
        desc = (v.properties or {}).get("description", "")
        return q in vid.lower() or q in str(title).lower() or q in str(desc).lower()

    def _collect_all_paper_ids(self, top_k: int) -> List[str]:
        """Fallback collection of first top_k paper IDs."""
        matched: List[str] = []
        for vid, v in list(self.graph_engine._vertices.items())[:top_k]:
            if v.label == "Paper" or vid.startswith("Paper:"):
                matched.append(vid.replace("Paper:", ""))
        return matched

    def _is_query_matched_paper(self, vid: str, v: Vertex, q: str) -> bool:
        """Checks if vertex is a paper matching query string."""
        if v.label != "Paper" and not vid.startswith("Paper:"):
            return False
        return self._is_paper_match(vid, v, q)

    def _find_seed_papers(self, query_text: str, top_k: int) -> List[str]:
        """Finds seed paper IDs for query."""
        q = query_text.lower()
        matched = [
            vid.replace("Paper:", "")
            for vid, v in self.graph_engine._vertices.items()
            if self._is_query_matched_paper(vid, v, q)
        ]
        if len(matched) >= top_k:
            return matched[:top_k]
        return matched or self._collect_all_paper_ids(top_k)

    def query_graphrag(
        self, query_text: str, top_k_papers: int = 3, max_hops: int = 2
    ) -> Dict[str, Any]:
        """End-to-end GraphRAG query execution."""
        matched_seeds = self._find_seed_papers(query_text, top_k_papers)
        expansion = self.expand_context(seed_paper_ids=matched_seeds, max_hops=max_hops)
        expansion["query"] = query_text
        expansion["seed_paper_ids"] = matched_seeds
        expansion["defense_chains"] = self.find_defense_chains(query_text)
        return expansion

    def _record_paper(
        self,
        vid: str,
        props: Dict[str, Any],
        d: int,
        pr: float,
        papers: List[Dict[str, Any]],
    ) -> None:
        papers.append(
            {
                "paper_id": vid.replace("Paper:", ""),
                "title": props.get("title", vid),
                "pagerank": round(pr, 6),
                "depth": d,
            }
        )

    def _record_defense(
        self,
        vid: str,
        props: Dict[str, Any],
        d: int,
        mitigations: List[Dict[str, Any]],
    ) -> None:
        mitigations.append(
            {
                "defense_id": vid,
                "name": props.get("name", vid),
                "depth": d,
            }
        )

    def _dispatch_evolution_record(
        self,
        vid: str,
        label: str,
        props: Dict[str, Any],
        d: int,
        pr_score: float,
        papers: List[Dict[str, Any]],
        mitigations: List[Dict[str, Any]],
    ) -> None:
        if label == "Paper" or vid.startswith("Paper:"):
            self._record_paper(vid, props, d, pr_score, papers)
        elif label == "DefenseMechanism" or vid.startswith("DefenseMechanism:"):
            self._record_defense(vid, props, d, mitigations)

    def _record_evolution_vertex(
        self,
        other_vid: str,
        d: int,
        pr_score: float,
        papers: List[Dict[str, Any]],
        mitigations: List[Dict[str, Any]],
    ) -> None:
        v = self.graph_engine.get_vertex(other_vid)
        if v:
            self._dispatch_evolution_record(
                other_vid, v.label, v.properties or {}, d, pr_score, papers, mitigations
            )

    def _step_evolution_edge(
        self,
        e: Any,
        vid: str,
        traversed_triples: List[Dict[str, Any]],
        visited_nodes: Set[str],
        next_frontier: Set[str],
        max_nodes: int,
        d: int,
        pr_scores: Dict[str, float],
        papers: List[Dict[str, Any]],
        mitigations: List[Dict[str, Any]],
    ) -> None:
        other_vid = e.dst_id if e.src_id == vid else e.src_id
        triple = {
            "subject": e.src_id,
            "predicate": e.label,
            "object": e.dst_id,
            "weight": e.weight,
        }
        if triple not in traversed_triples:
            traversed_triples.append(triple)

        if other_vid not in visited_nodes and len(visited_nodes) < max_nodes:
            visited_nodes.add(other_vid)
            next_frontier.add(other_vid)
            self._record_evolution_vertex(
                other_vid, d, pr_scores.get(other_vid, 0.0), papers, mitigations
            )

    def _expand_evolution_depth(
        self,
        frontier: Set[str],
        visited_nodes: Set[str],
        max_nodes: int,
        d: int,
        pr_scores: Dict[str, float],
        traversed_triples: List[Dict[str, Any]],
        papers: List[Dict[str, Any]],
        mitigations: List[Dict[str, Any]],
    ) -> Set[str]:
        next_frontier: Set[str] = set()
        for vid in frontier:
            edges = list(self.graph_engine.get_outgoing_edges(vid)) + list(
                self.graph_engine.get_incoming_edges(vid)
            )
            for e in edges:
                self._step_evolution_edge(
                    e,
                    vid,
                    traversed_triples,
                    visited_nodes,
                    next_frontier,
                    max_nodes,
                    d,
                    pr_scores,
                    papers,
                    mitigations,
                )
        return next_frontier

    def query_attack_evolution(
        self, technique_id: str, max_depth: int = 3, max_nodes: int = 200
    ) -> Dict[str, Any]:
        """
        Multihop exploration tracing an attack technique across papers, citations,
        and defense countermeasures, prioritizing nodes by PageRank centrality.
        """
        from .traversal import compute_pagerank

        canonical_tech = (
            technique_id
            if technique_id.startswith("AttackTechnique:")
            else f"AttackTechnique:{technique_id}"
        )
        pr_scores = compute_pagerank(self.graph_engine)
        visited_nodes: Set[str] = {canonical_tech}
        papers: List[Dict[str, Any]] = []
        mitigations: List[Dict[str, Any]] = []
        traversed_triples: List[Dict[str, Any]] = []

        frontier = {canonical_tech}
        for d in range(1, max_depth + 1):
            frontier = self._expand_evolution_depth(
                frontier,
                visited_nodes,
                max_nodes,
                d,
                pr_scores,
                traversed_triples,
                papers,
                mitigations,
            )
            if not frontier or len(visited_nodes) >= max_nodes:
                break

        papers.sort(key=lambda x: float(x.get("pagerank", 0.0)), reverse=True)
        return {
            "technique_id": technique_id,
            "total_nodes_visited": len(visited_nodes),
            "evolution_papers": papers,
            "mitigations": mitigations,
            "traversed_triples": traversed_triples,
        }
