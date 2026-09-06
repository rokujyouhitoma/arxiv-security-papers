#!/usr/bin/env python3
"""
Ontology Core Module.
Pure Python, domain-independent ontology AST, DSL, parser, validator, and code generators.
"""

from .ast import (
    ASTNode,
    AxiomNode,
    AxiomType,
    ClassNode,
    DatatypePropertyNode,
    InstanceNode,
    MetadataNode,
    ObjectPropertyNode,
    OntologyDocumentNode,
    PropertyNode,
)
from .codegen_turtle import TurtleCodeGenerator
from .dsl import (
    ClassDeclaration,
    DatatypePropertyField,
    ObjectPropertyField,
    PropertyField,
    ontology_class,
)
from .interpreter import ASTVisitor, OntologyInterpreter
from .parser import OntologyParser
from .validator import Diagnostic, DiagnosticSeverity, SemanticValidator

__all__ = [
    "ASTNode",
    "AxiomNode",
    "AxiomType",
    "ClassNode",
    "DatatypePropertyNode",
    "InstanceNode",
    "MetadataNode",
    "ObjectPropertyNode",
    "OntologyDocumentNode",
    "PropertyNode",
    "TurtleCodeGenerator",
    "ClassDeclaration",
    "DatatypePropertyField",
    "ObjectPropertyField",
    "PropertyField",
    "ontology_class",
    "ASTVisitor",
    "OntologyInterpreter",
    "OntologyParser",
    "Diagnostic",
    "DiagnosticSeverity",
    "SemanticValidator",
]
