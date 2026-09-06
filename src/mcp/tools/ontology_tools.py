#!/usr/bin/env python3
"""
Ontology Causal Chain and Evidence Inspection Tools for MCP (Issue 200, DSN-10, DSN-22).
Provides CausalChainFinder for attack-to-defense causal pathways and EvidenceInspector
for empirical benchmark evaluation and claim provenance verification.
"""

from __future__ import annotations

import os
import re
from typing import Any, Dict, List, Optional

from graph.engine import PropertyGraphEngine
from graph.structures import Vertex


def _get_default_workspace() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if (
            os.path.exists(os.path.join(cur, "pyproject.toml"))
            or os.path.exists(os.path.join(cur, "Makefile"))
            or os.path.exists(os.path.join(cur, ".agents"))
        ):
            return cur
        cur = os.path.dirname(cur)
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def _sanitize_identifier(val: Any) -> str:
    """Sanitizes external input string, allowing alphanumeric, colons, dots, hyphens, and underscores."""
    if not isinstance(val, str):
        return ""
    cleaned = re.sub(r"[^\w\.\:\-\/]", "", val.strip())
    return cleaned[:128]


class CausalChainFinder:
    """
    Traverses Full-Spectrum SKO property graph to discover causal defense pathways:
    AttackTechnique -> Precondition -> NeutralizedBy -> DefenseMechanism -> Mitigation/Rule.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        graph_engine: Optional[PropertyGraphEngine] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or _get_default_workspace()
        self._engine: Optional[PropertyGraphEngine] = graph_engine

    def _get_engine(self) -> PropertyGraphEngine:
        if self._engine is None:
            self._engine = PropertyGraphEngine(workspace_dir=self.workspace_dir)
        return self._engine

    def _find_by_prefix(
        self, engine: PropertyGraphEngine, target_id: str
    ) -> Optional[Vertex]:
        for prefix in ("AttackTechnique:", "Vulnerability:", "ThreatActor:"):
            v = engine.get_vertex(f"{prefix}{target_id}")
            if v is not None:
                return v
        return None

    def _find_by_property(
        self, engine: PropertyGraphEngine, target_lower: str
    ) -> Optional[Vertex]:
        for vtx in engine.get_all_vertices():
            v_name = str(vtx.properties.get("name", "")).lower()
            v_tech = str(vtx.properties.get("technique_id", "")).lower()
            if target_lower in (vtx.id.lower(), v_name, v_tech):
                return vtx
        return None

    def _find_matching_vertex(self, target_id: str) -> Optional[Vertex]:
        engine = self._get_engine()
        v = engine.get_vertex(target_id)
        if v is not None:
            return v
        prefixed = self._find_by_prefix(engine, target_id)
        if prefixed is not None:
            return prefixed
        return self._find_by_property(engine, target_id.lower())

    def _collect_impacts(
        self, vertex_id: str, min_confidence: float
    ) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        impacts: List[Dict[str, Any]] = []
        for edge in engine.get_out_edges(
            vertex_id, "HAS_IMPACT", min_confidence=min_confidence
        ):
            dst = engine.get_vertex(edge.dst_id)
            impacts.append(
                {
                    "impact_id": edge.dst_id,
                    "label": dst.label if dst else "Impact",
                    "properties": dst.properties if dst else {},
                    "confidence": edge.get_confidence(),
                    "rule": edge.properties.get("inference_rule_id", ""),
                }
            )
        return impacts

    def _resolve_neutralizing_defenses(
        self, pre_id: str, min_confidence: float
    ) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        defenses: List[Dict[str, Any]] = []
        for edge in engine.get_in_edges(
            pre_id, "NEUTRALIZES_PRECONDITION", min_confidence=min_confidence
        ):
            def_vtx = engine.get_vertex(edge.src_id)
            defenses.append(
                {
                    "defense_id": edge.src_id,
                    "name": (
                        def_vtx.properties.get("name", edge.src_id)
                        if def_vtx
                        else edge.src_id
                    ),
                    "properties": def_vtx.properties if def_vtx else {},
                    "confidence": edge.get_confidence(),
                    "rule": edge.properties.get("inference_rule_id", ""),
                }
            )
        return defenses

    def _collect_preconditions(
        self, vertex_id: str, min_confidence: float
    ) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        preconditions: List[Dict[str, Any]] = []
        for edge in engine.get_out_edges(
            vertex_id, "REQUIRES_PRECONDITION", min_confidence=min_confidence
        ):
            pre_vtx = engine.get_vertex(edge.dst_id)
            neutralizers = self._resolve_neutralizing_defenses(
                edge.dst_id, min_confidence
            )
            preconditions.append(
                {
                    "precondition_id": edge.dst_id,
                    "name": (
                        pre_vtx.properties.get("name", edge.dst_id)
                        if pre_vtx
                        else edge.dst_id
                    ),
                    "properties": pre_vtx.properties if pre_vtx else {},
                    "confidence": edge.get_confidence(),
                    "neutralized_by": neutralizers,
                }
            )
        return preconditions

    def _collect_direct_mitigations(
        self, vertex_id: str, min_confidence: float
    ) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        mitigations: List[Dict[str, Any]] = []
        for edge in engine.get_in_edges(
            vertex_id, "MITIGATES", "PATCHES", min_confidence=min_confidence
        ):
            src_vtx = engine.get_vertex(edge.src_id)
            mitigations.append(
                {
                    "defense_id": edge.src_id,
                    "predicate": edge.label,
                    "name": (
                        src_vtx.properties.get("name", edge.src_id)
                        if src_vtx
                        else edge.src_id
                    ),
                    "properties": src_vtx.properties if src_vtx else {},
                    "confidence": edge.get_confidence(),
                    "rule": edge.properties.get("inference_rule_id", ""),
                }
            )
        return mitigations

    def find_defense_chains(
        self,
        threat_id: str,
        max_depth: int = 3,
        min_confidence: float = 0.0,
    ) -> Dict[str, Any]:
        """Discovers causal defense pathways for the specified threat identifier."""
        clean_id = _sanitize_identifier(threat_id)
        if not clean_id:
            return {"status": "error", "message": "Invalid or empty threat_id"}

        target_vtx = self._find_matching_vertex(clean_id)
        if not target_vtx:
            return {
                "status": "not_found",
                "message": f"Threat entity '{clean_id}' not found in ontology graph",
                "threat_id": clean_id,
                "chains": [],
            }

        effective_conf = max(0.0, min(1.0, float(min_confidence)))
        impacts = self._collect_impacts(target_vtx.id, effective_conf)
        preconditions = self._collect_preconditions(target_vtx.id, effective_conf)
        direct_mitigations = self._collect_direct_mitigations(
            target_vtx.id, effective_conf
        )

        return {
            "status": "success",
            "threat_id": target_vtx.id,
            "threat_name": target_vtx.properties.get("name", target_vtx.id),
            "threat_label": target_vtx.label,
            "impacts": impacts,
            "preconditions": preconditions,
            "direct_mitigations": direct_mitigations,
            "summary": {
                "impact_count": len(impacts),
                "precondition_count": len(preconditions),
                "direct_mitigation_count": len(direct_mitigations),
            },
        }


class EvidenceInspector:
    """
    Inspects and aggregates empirical evidence, benchmarks, and claims in Full-Spectrum SKO:
    Paper -> AssertsClaim -> Claim -> YieldsEvaluation / Evaluates -> EvaluationResult / PoCArtifact.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        graph_engine: Optional[PropertyGraphEngine] = None,
    ) -> None:
        self.workspace_dir = workspace_dir or _get_default_workspace()
        self._engine: Optional[PropertyGraphEngine] = graph_engine

    def _get_engine(self) -> PropertyGraphEngine:
        if self._engine is None:
            self._engine = PropertyGraphEngine(workspace_dir=self.workspace_dir)
        return self._engine

    def _resolve_entity(self, entity_id: str) -> Optional[Vertex]:
        engine = self._get_engine()
        v = engine.get_vertex(entity_id)
        if v is not None:
            return v
        for prefix in ("Paper:", "Claim:", "EvaluationResult:", "PoCArtifact:"):
            v = engine.get_vertex(f"{prefix}{entity_id}")
            if v is not None:
                return v
        return None

    def _gather_claims(self, root_id: str) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        claims: List[Dict[str, Any]] = []
        for edge in engine.get_out_edges(root_id, "ASSERTS_CLAIM"):
            c_vtx = engine.get_vertex(edge.dst_id)
            claims.append(
                {
                    "claim_id": edge.dst_id,
                    "description": (
                        c_vtx.properties.get("description", "") if c_vtx else ""
                    ),
                    "properties": c_vtx.properties if c_vtx else {},
                    "confidence": edge.get_confidence(),
                }
            )
        return claims

    def _gather_evaluations(self, root_id: str) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        evaluations: List[Dict[str, Any]] = []
        for edge in engine.get_out_edges(
            root_id, "YIELDS_EVALUATION", "EVALUATES", "EVALUATES_CLAIM"
        ):
            ev_vtx = engine.get_vertex(edge.dst_id)
            evaluations.append(
                {
                    "evaluation_id": edge.dst_id,
                    "predicate": edge.label,
                    "properties": ev_vtx.properties if ev_vtx else {},
                    "confidence": edge.get_confidence(),
                    "evidence_snippet": edge.properties.get("evidence_snippet", ""),
                }
            )
        return evaluations

    def _gather_pocs(self, root_id: str) -> List[Dict[str, Any]]:
        engine = self._get_engine()
        pocs: List[Dict[str, Any]] = []
        for edge in engine.get_out_edges(root_id, "HAS_POC"):
            poc_vtx = engine.get_vertex(edge.dst_id)
            pocs.append(
                {
                    "poc_id": edge.dst_id,
                    "properties": poc_vtx.properties if poc_vtx else {},
                    "confidence": edge.get_confidence(),
                }
            )
        return pocs

    def get_evidence_for_entity(
        self,
        entity_id: str,
        include_pocs: bool = True,
    ) -> Dict[str, Any]:
        """Extracts claims, empirical evaluations, benchmarks, and PoC artifacts for an entity."""
        clean_id = _sanitize_identifier(entity_id)
        if not clean_id:
            return {"status": "error", "message": "Invalid or empty entity_id"}

        target_vtx = self._resolve_entity(clean_id)
        if not target_vtx:
            return {
                "status": "not_found",
                "message": f"Entity '{clean_id}' not found in ontology graph",
                "entity_id": clean_id,
            }

        claims = self._gather_claims(target_vtx.id)
        evaluations = self._gather_evaluations(target_vtx.id)
        pocs = self._gather_pocs(target_vtx.id) if include_pocs else []

        return {
            "status": "success",
            "entity_id": target_vtx.id,
            "label": target_vtx.label,
            "properties": target_vtx.properties,
            "claims": claims,
            "evaluations": evaluations,
            "pocs": pocs,
            "evidence_count": len(claims) + len(evaluations) + len(pocs),
        }
