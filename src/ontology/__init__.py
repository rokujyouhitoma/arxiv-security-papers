#!/usr/bin/env python3
"""
Security Knowledge Ontology (SKO) Package.
Provides standardized entity schemas, relationship predicates, taxonomy mappings,
and fact triple extraction.
"""

from .extractor import OntologyExtractor
from .rule_registry import EdgeInferenceRuleRegistry
from .rule_schema import (
    ConfidenceTier,
    EdgeInferenceRule,
    EvidenceExtractionSpec,
    RuleConditionType,
)
from .schema import (
    AttackTechniqueEntity,
    BaseEntity,
    BenchmarkMetricEntity,
    DefenseMechanismEntity,
    EntityType,
    PaperEntity,
    Predicate,
    SecurityOntologySchema,
    TargetAssetEntity,
    ThreatActorEntity,
    Triple,
    VulnerabilityEntity,
)
from .taxonomy import TaxonomyRegistry
from .turtle_engine import (
    URI,
    DatatypeProperty,
    Literal,
    ObjectProperty,
    OntologyClass,
    OntologyInstance,
    OntologyMetadata,
    RawTriple,
    RDFTerm,
    TurtleDocumentBuilder,
    build_sample_enterprise_ontology,
    build_security_cti_ontology,
)

__all__ = [
    "EntityType",
    "Predicate",
    "BaseEntity",
    "PaperEntity",
    "ThreatActorEntity",
    "AttackTechniqueEntity",
    "VulnerabilityEntity",
    "TargetAssetEntity",
    "DefenseMechanismEntity",
    "BenchmarkMetricEntity",
    "Triple",
    "SecurityOntologySchema",
    "TaxonomyRegistry",
    "OntologyExtractor",
    "RuleConditionType",
    "ConfidenceTier",
    "EvidenceExtractionSpec",
    "EdgeInferenceRule",
    "EdgeInferenceRuleRegistry",
    "RDFTerm",
    "URI",
    "Literal",
    "OntologyMetadata",
    "OntologyClass",
    "ObjectProperty",
    "DatatypeProperty",
    "OntologyInstance",
    "RawTriple",
    "TurtleDocumentBuilder",
    "build_sample_enterprise_ontology",
    "build_security_cti_ontology",
]
