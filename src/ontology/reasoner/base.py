"""
Base interfaces and data structures for Pure Python OWL Reasoner.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Tuple


class ClashType(str, Enum):
    """Classification of logic clashes detected by Tableaux engine."""

    ATOMIC_CONTRADICTION = "AtomicContradiction"  # A(x) and not A(x)
    DISJOINT_CLASSES = "DisjointClasses"  # x in C and x in D where C disjointWith D
    BOTTOM_CONCEPT = "BottomConcept"  # x in Nothing (owl:Nothing / bot)
    MAX_CARDINALITY = "MaxCardinalityViolation"  # Number of role fillers exceeds max


@dataclass(frozen=True)
class Clash:
    """Represents an explicit logical contradiction encountered in the Tableau branch."""

    clash_type: ClashType
    node_id: str
    conflicting_concepts: Tuple[str, ...]
    justification_axioms: Tuple[str, ...]
    explanation_message: str

    def to_dict(self) -> Dict[str, Any]:
        """Converts Clash instance to dictionary representation."""
        return {
            "clash_type": self.clash_type.value,
            "node_id": self.node_id,
            "conflicting_concepts": list(self.conflicting_concepts),
            "justification_axioms": list(self.justification_axioms),
            "explanation_message": self.explanation_message,
        }


@dataclass
class ConsistencyReport:
    """Audit report for ontology consistency and subsumption checking."""

    is_consistent: bool
    unsatisfiable_classes: List[str] = field(default_factory=list)
    clashes: List[Clash] = field(default_factory=list)
    inferred_subclasses: Dict[str, List[str]] = field(default_factory=dict)
    materialized_triples_count: int = 0
    explanation: str = ""
    reasoner_engine: str = "PurePython-Hypertableau-Datalog"

    def to_dict(self) -> Dict[str, Any]:
        """Converts report to dictionary representation."""
        return {
            "is_consistent": self.is_consistent,
            "unsatisfiable_classes": self.unsatisfiable_classes,
            "clashes": [c.to_dict() for c in self.clashes],
            "inferred_subclasses": self.inferred_subclasses,
            "materialized_triples_count": self.materialized_triples_count,
            "explanation": self.explanation,
            "reasoner_engine": self.reasoner_engine,
        }


class AbstractReasoner(ABC):
    """Abstract interface for Pure Python OWL reasoners."""

    @abstractmethod
    def check_consistency(self) -> ConsistencyReport:
        """Checks logical consistency of the loaded ontology knowledge base."""
        pass

    @abstractmethod
    def is_subclass_of(self, sub_class: str, super_class: str) -> bool:
        """Tests whether sub_class is subsumed by super_class under current axioms."""
        pass

    @abstractmethod
    def materialize_inferences(self) -> int:
        """Runs forward-chaining deduction and materializes implicit triples."""
        pass
