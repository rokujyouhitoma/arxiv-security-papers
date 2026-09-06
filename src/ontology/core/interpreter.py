#!/usr/bin/env python3
"""
Ontology AST Interpreter & Visitor Framework.
Provides an extensible visitor pattern for evaluating, analyzing, and compiling
the OntologyDocumentNode AST into multiple backends.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from .ast import (
    AxiomNode,
    ClassNode,
    DatatypePropertyNode,
    InstanceNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
)


class ASTVisitor(ABC):
    """Abstract Visitor for traversing ontology AST nodes."""

    @abstractmethod
    def visit_metadata(self, node: MetadataNode) -> None:
        """Processes ontology metadata header."""
        pass

    @abstractmethod
    def visit_class(self, node: ClassNode) -> None:
        """Processes an owl:Class node."""
        pass

    @abstractmethod
    def visit_object_property(self, node: ObjectPropertyNode) -> None:
        """Processes an owl:ObjectProperty node."""
        pass

    @abstractmethod
    def visit_datatype_property(self, node: DatatypePropertyNode) -> None:
        """Processes an owl:DatatypeProperty node."""
        pass

    @abstractmethod
    def visit_axiom(self, node: AxiomNode) -> None:
        """Processes an ontology axiom node."""
        pass

    @abstractmethod
    def visit_instance(self, node: InstanceNode) -> None:
        """Processes an ABox individual instance node."""
        pass


class OntologyInterpreter:
    """
    Interprets an OntologyDocumentNode by driving registered AST visitors.
    """

    def __init__(self, doc: OntologyDocumentNode) -> None:
        self.doc = doc

    def _walk_classes(self, visitor: ASTVisitor) -> None:
        """Walks all defined class nodes in sorted order."""
        for c_uri in sorted(self.doc.classes.keys()):
            visitor.visit_class(self.doc.classes[c_uri])

    def _walk_properties(self, visitor: ASTVisitor) -> None:
        """Walks all defined object and datatype property nodes."""
        for op_uri in sorted(self.doc.object_properties.keys()):
            visitor.visit_object_property(self.doc.object_properties[op_uri])
        for dp_uri in sorted(self.doc.datatype_properties.keys()):
            visitor.visit_datatype_property(self.doc.datatype_properties[dp_uri])

    def _walk_axioms_and_instances(self, visitor: ASTVisitor) -> None:
        """Walks all axioms and ABox instance nodes."""
        for ax in self.doc.axioms:
            visitor.visit_axiom(ax)
        for i_uri in sorted(self.doc.instances.keys()):
            visitor.visit_instance(self.doc.instances[i_uri])

    def interpret(self, visitor: ASTVisitor) -> None:
        """Executes full traversal of the ontology AST with the given visitor."""
        visitor.visit_metadata(self.doc.metadata)
        self._walk_classes(visitor)
        self._walk_properties(visitor)
        self._walk_axioms_and_instances(visitor)
