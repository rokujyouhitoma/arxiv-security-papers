#!/usr/bin/env python3
"""
Security Domain Ontology Axioms.
Formal logical axioms (Disjointness, Transitivity, Inverse relationships) in CTI.
"""

from __future__ import annotations

from typing import List, Tuple

from ..core.ast import AxiomNode, AxiomType

# Pairwise mutually disjoint domain concepts
DISJOINT_CLASS_PAIRS: List[Tuple[str, str]] = [
    ("sec:AttackTechnique", "sec:DefenseMechanism"),
    ("sec:AttackTechnique", "sec:Vulnerability"),
    ("sec:DefenseMechanism", "sec:Vulnerability"),
    ("sec:ThreatActor", "sec:TargetAsset"),
    ("sec:Paper", "sec:Incident"),
]


def create_security_axioms() -> List[AxiomNode]:
    """Generates standard axiomatic constraints for security ontology."""
    axioms: List[AxiomNode] = []
    for c1, c2 in DISJOINT_CLASS_PAIRS:
        axioms.append(
            AxiomNode(
                axiom_type=AxiomType.DISJOINT,
                subject_uri=c1,
                target_uri=c2,
            )
        )
    return axioms
