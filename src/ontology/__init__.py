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
]
