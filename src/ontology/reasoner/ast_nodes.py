"""
Description Logic (DL) Abstract Syntax Tree (AST) Nodes and Axioms.
Provides formal representations for OWL 2 concepts, roles, and TBox/ABox axioms.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Tuple


class DLNode(ABC):
    """Abstract base class for all Description Logic AST nodes."""

    @abstractmethod
    def to_manchester(self) -> str:
        """Renders the concept expression in Manchester Syntax."""
        pass


class Concept(DLNode):
    """Base class for Description Logic concept expressions."""

    pass


@dataclass(frozen=True)
class TopConcept(Concept):
    """owl:Thing / Top concept (⊤)."""

    def to_manchester(self) -> str:
        return "owl:Thing"


@dataclass(frozen=True)
class BottomConcept(Concept):
    """owl:Nothing / Bottom concept (⊥)."""

    def to_manchester(self) -> str:
        return "owl:Nothing"


@dataclass(frozen=True)
class AtomicConcept(Concept):
    """Named class entity A."""

    name: str

    def to_manchester(self) -> str:
        return self.name


@dataclass(frozen=True)
class ComplementConcept(Concept):
    """Negation of a concept ¬C."""

    concept: Concept

    def to_manchester(self) -> str:
        return f"(not {self.concept.to_manchester()})"


@dataclass(frozen=True)
class IntersectionConcept(Concept):
    """Conjunction of concepts C ⊓ D."""

    operands: Tuple[Concept, ...]

    def to_manchester(self) -> str:
        inner = " and ".join(c.to_manchester() for c in self.operands)
        return f"({inner})"


@dataclass(frozen=True)
class UnionConcept(Concept):
    """Disjunction of concepts C ⊔ D."""

    operands: Tuple[Concept, ...]

    def to_manchester(self) -> str:
        inner = " or ".join(c.to_manchester() for c in self.operands)
        return f"({inner})"


@dataclass(frozen=True)
class ExistentialRestriction(Concept):
    """Existential quantification ∃R.C."""

    property_name: str
    filler: Concept

    def to_manchester(self) -> str:
        return f"({self.property_name} some {self.filler.to_manchester()})"


@dataclass(frozen=True)
class UniversalRestriction(Concept):
    """Universal quantification ∀R.C."""

    property_name: str
    filler: Concept

    def to_manchester(self) -> str:
        return f"({self.property_name} only {self.filler.to_manchester()})"


class Axiom(DLNode):
    """Base class for TBox, RBox, and ABox axioms."""

    pass


@dataclass(frozen=True)
class SubClassOfAxiom(Axiom):
    """Subclass axiom C ⊑ D."""

    sub_concept: Concept
    super_concept: Concept

    def to_manchester(self) -> str:
        return f"{self.sub_concept.to_manchester()} SubClassOf {self.super_concept.to_manchester()}"


@dataclass(frozen=True)
class DisjointClassesAxiom(Axiom):
    """Disjoint classes axiom C ⊓ D ⊑ ⊥."""

    classes: Tuple[Concept, ...]

    def to_manchester(self) -> str:
        items = ", ".join(c.to_manchester() for c in self.classes)
        return f"DisjointClasses: {items}"


@dataclass(frozen=True)
class SubPropertyOfAxiom(Axiom):
    """Subproperty axiom R ⊑ S."""

    sub_property: str
    super_property: str

    def to_manchester(self) -> str:
        return f"{self.sub_property} SubPropertyOf {self.super_property}"


@dataclass(frozen=True)
class InversePropertyAxiom(Axiom):
    """Inverse properties axiom R ≡ S⁻."""

    property_a: str
    property_b: str

    def to_manchester(self) -> str:
        return f"{self.property_a} InverseOf {self.property_b}"


@dataclass(frozen=True)
class TransitivePropertyAxiom(Axiom):
    """Transitive property axiom R⁺ ⊑ R."""

    property_name: str

    def to_manchester(self) -> str:
        return f"Characteristics: Transitive {self.property_name}"


@dataclass(frozen=True)
class ClassAssertionAxiom(Axiom):
    """ABox class assertion a : C."""

    individual: str
    concept: Concept

    def to_manchester(self) -> str:
        return f"Individual: {self.individual} Type: {self.concept.to_manchester()}"


@dataclass(frozen=True)
class PropertyAssertionAxiom(Axiom):
    """ABox role assertion (a, b) : R."""

    subject: str
    property_name: str
    target: str

    def to_manchester(self) -> str:
        return f"Individual: {self.subject} Facts: {self.property_name} {self.target}"
