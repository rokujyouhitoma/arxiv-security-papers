#!/usr/bin/env python3
"""
Ontology Abstract Syntax Tree (AST) & Intermediate Representation (IR).
Domain-independent core data structures representing ontology syntax and semantics.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple


class AxiomType(str, Enum):
    """Core ontological axiom classifications."""

    SUBCLASS = "SubClassOf"
    DISJOINT = "DisjointWith"
    INVERSE = "InverseOf"
    TRANSITIVE = "Transitive"
    SYMMETRIC = "Symmetric"
    EQUIVALENT = "EquivalentTo"


@dataclass
class ASTNode:
    """Abstract base node for all ontology syntax tree elements."""

    uri: str
    label: str = ""
    comment: str = ""
    properties: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PropertyNode(ASTNode):
    """Base node for ontology properties (relations and attributes)."""

    domain: Optional[str] = None
    range_: Optional[str] = None
    is_functional: bool = False


@dataclass
class ObjectPropertyNode(PropertyNode):
    """AST node for owl:ObjectProperty relating entity instances."""

    inverse_of: Optional[str] = None
    is_transitive: bool = False
    is_symmetric: bool = False


@dataclass
class DatatypePropertyNode(PropertyNode):
    """AST node for owl:DatatypeProperty assigning literal attributes."""

    pass


@dataclass
class AxiomNode:
    """AST node representing formal axioms and logical constraints."""

    axiom_type: AxiomType
    subject_uri: str
    target_uri: str
    properties: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ClassNode(ASTNode):
    """AST node representing owl:Class definitions and structural hierarchies."""

    sub_class_of: Optional[str] = None
    disjoint_with: List[str] = field(default_factory=list)
    declared_properties: List[str] = field(default_factory=list)


@dataclass
class InstanceNode(ASTNode):
    """AST node representing ABox individuals and factual instances."""

    rdf_types: List[str] = field(default_factory=list)
    statements: List[Tuple[str, Any]] = field(default_factory=list)


@dataclass
class MetadataNode:
    """AST node for ontology container metadata header."""

    uri: str
    label: str = ""
    comment: str = ""
    version_info: str = "1.0.0"
    imports: List[str] = field(default_factory=list)


@dataclass
class OntologyDocumentNode:
    """Root AST node representing a complete ontology compilation unit."""

    metadata: MetadataNode
    prefixes: Dict[str, str] = field(default_factory=dict)
    classes: Dict[str, ClassNode] = field(default_factory=dict)
    object_properties: Dict[str, ObjectPropertyNode] = field(default_factory=dict)
    datatype_properties: Dict[str, DatatypePropertyNode] = field(default_factory=dict)
    axioms: List[AxiomNode] = field(default_factory=list)
    instances: Dict[str, InstanceNode] = field(default_factory=dict)

    def add_prefix(self, prefix: str, iri: str) -> None:
        """Registers a namespace prefix."""
        self.prefixes[prefix] = iri

    def get_all_uris(self) -> Set[str]:
        """Returns the set of all declared URIs across classes and properties."""
        uris = set(self.classes.keys())
        uris.update(self.object_properties.keys())
        uris.update(self.datatype_properties.keys())
        return uris
