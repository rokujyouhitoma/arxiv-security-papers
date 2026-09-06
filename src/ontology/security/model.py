#!/usr/bin/env python3
"""
Security Knowledge Ontology (SKO) Model Integration.
Assembles the complete security ontology AST and compiles it using the core interpreter.
"""

from __future__ import annotations

from typing import Dict, List, Type

from ..core.ast import OntologyDocumentNode
from ..core.codegen_turtle import TurtleCodeGenerator
from ..core.parser import OntologyParser
from ..core.validator import DiagnosticSeverity, SemanticValidator
from .axioms import create_security_axioms
from .classes import (
    AttackTechnique,
    BenchmarkMetric,
    DefenseMechanism,
    DetectionRule,
    Incident,
    Paper,
    PoCArtifact,
    Precondition,
    PublicationVenue,
    ResearchGap,
    ResidualRisk,
    TargetAsset,
    ThreatActor,
    Vulnerability,
)

SECURITY_PREFIXES: Dict[str, str] = {
    "owl": "http://www.w3.org/2002/07/owl#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "sec": "https://arxiv-security-papers.org/ontology/security#",
    "xsd": "http://www.w3.org/2001/XMLSchema#",
}

ALL_SECURITY_CLASSES: List[Type[object]] = [
    Paper,
    ThreatActor,
    AttackTechnique,
    Vulnerability,
    TargetAsset,
    DefenseMechanism,
    BenchmarkMetric,
    Incident,
    DetectionRule,
    PoCArtifact,
    Precondition,
    ResearchGap,
    ResidualRisk,
    PublicationVenue,
]


def build_security_ontology_ast() -> OntologyDocumentNode:
    """
    Parses security classes into an OntologyDocumentNode AST and validates semantic constraints.
    """
    parser = OntologyParser(
        base_uri="https://arxiv-security-papers.org/ontology/security",
        label="arXiv Security Papers CTI Knowledge Ontology",
        comment="セキュリティ学術論文、サイバー脅威、攻撃手法、脆弱性、および防御策を推論・連携するための知識オントロジーモデル",
        version_info="2.0.0",
        prefixes=SECURITY_PREFIXES,
    )
    doc = parser.parse_classes(ALL_SECURITY_CLASSES)
    doc.axioms.extend(create_security_axioms())

    diagnostics = SemanticValidator.validate(doc)
    errors = [d for d in diagnostics if d.severity == DiagnosticSeverity.ERROR]
    if errors:
        msg = f"Ontology AST semantic validation failed: {errors[0].message}"
        raise ValueError(msg)

    return doc


def export_security_ontology_turtle() -> str:
    """
    Compiles the Security Knowledge Ontology AST into standard W3C Turtle (.ttl).
    """
    doc = build_security_ontology_ast()
    return TurtleCodeGenerator.compile_document(doc)
