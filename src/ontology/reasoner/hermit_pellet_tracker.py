"""
Reference tracking and comparison specification for HermiT and Pellet reasoners.
Documents formal algorithmic correspondences, complexity bounds, and design mappings.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List


@dataclass(frozen=True)
class ReasonerReferenceProfile:
    """Detailed profile of a reference Description Logic reasoner."""

    name: str
    organization: str
    core_algorithm: str
    supported_profile: str
    worst_case_complexity: str
    key_optimizations: List[str]
    pure_python_correspondence: str


HERMIT_REFERENCE = ReasonerReferenceProfile(
    name="HermiT",
    organization="University of Oxford (Ian Horrocks, Boris Motik, Rob Shearer)",
    core_algorithm="Hypertableau Calculus",
    supported_profile="W3C OWL 2 DL (SROIQ^D)",
    worst_case_complexity="2-NEXPTIME-complete",
    key_optimizations=[
        "DL-Clause normalization to reduce non-deterministic disjunctive branching",
        "Deterministic-rule-first saturation strategy",
        "Pairwise and core blocking for termination guarantees",
        "Individual reuse in nominal generation",
    ],
    pure_python_correspondence=(
        "src/ontology/reasoner/tableaux.py: Deterministic-first expansion loop, "
        "Hypertableau-style clause clustering, and subset blocking scheme."
    ),
)

PELLET_REFERENCE = ReasonerReferenceProfile(
    name="Pellet",
    organization="Clark & Parsia / University of Maryland (Evren Sirin, Bijan Parsia)",
    core_algorithm="Tableau Algorithm with Dependency Directed Backtracking",
    supported_profile="W3C OWL 2 DL (SROIQ^D) + SWRL Rules",
    worst_case_complexity="2-NEXPTIME-complete",
    key_optimizations=[
        "Dependency-directed backtracking (Backjumping) on clash detection",
        "Axiom tracing for Minimal Unsatisfiable Sub-ontology (MUS / Justification)",
        "ABox partitioning and absorption heuristics",
        "DL-Safe rule engine integration",
    ],
    pure_python_correspondence=(
        "src/ontology/reasoner/explanation.py: Conflict dependency tracking, "
        "Minimal Clash Justification tracing, and DL-Safe Datalog forward chaining."
    ),
)


class ReferenceReasonerTracker:
    """Utility providing tracking metadata and comparative audit telemetry."""

    @staticmethod
    def get_reference_profiles() -> Dict[str, Dict[str, Any]]:
        """Returns structured comparison metadata for HermiT and Pellet."""
        return {
            "HermiT": {
                "organization": HERMIT_REFERENCE.organization,
                "algorithm": HERMIT_REFERENCE.core_algorithm,
                "profile": HERMIT_REFERENCE.supported_profile,
                "complexity": HERMIT_REFERENCE.worst_case_complexity,
                "optimizations": HERMIT_REFERENCE.key_optimizations,
                "pure_python_mapping": HERMIT_REFERENCE.pure_python_correspondence,
            },
            "Pellet": {
                "organization": PELLET_REFERENCE.organization,
                "algorithm": PELLET_REFERENCE.core_algorithm,
                "profile": PELLET_REFERENCE.supported_profile,
                "complexity": PELLET_REFERENCE.worst_case_complexity,
                "optimizations": PELLET_REFERENCE.key_optimizations,
                "pure_python_mapping": PELLET_REFERENCE.pure_python_correspondence,
            },
        }

    @staticmethod
    def get_profile(name: str) -> ReasonerReferenceProfile:
        """Retrieves profile by name ('HermiT' or 'Pellet')."""
        if name.lower() == "hermit":
            return HERMIT_REFERENCE
        return PELLET_REFERENCE

    @staticmethod
    def get_summary_narrative() -> str:
        """Returns human-readable narrative of the reference tracking approach."""
        return (
            "The Pure Python OWL Reasoner tracks HermiT's Hypertableau branching reduction "
            "and Pellet's dependency-directed clash justification. It separates heavy DL "
            "Tableau checking on TBox axioms from polynomial-time (PTime) OWL 2 RL Datalog "
            "forward chaining over large ABox instances."
        )


# Canonical alias for compatibility
HermiTPelletSpecificationTracker = ReferenceReasonerTracker
