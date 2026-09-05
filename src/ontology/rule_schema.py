#!/usr/bin/env python3
"""
Edge Inference Rule Ontology Master (EIROM) Schema Definition.
Defines typed data structures, condition enums, evidence specs,
and validation logic for graph edge inference rules.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, Dict

# Pattern to detect dangerous nested quantifiers (basic ReDoS heuristic: (a+)+ or (a*)*)
REDOS_SUSPECT_PATTERN = re.compile(r"\([^)]*[\+\*][^)]*\)[\+\*]")


class RuleConditionType(str, Enum):
    """Enumeration of supported rule condition evaluation mechanisms."""

    REGEX = "regex"
    LEXICAL = "lexical"
    SEMANTIC_THRESHOLD = "semantic_threshold"
    CATALOG_AXIOM = "catalog_axiom"
    CONTEXT_RATIO = "context_ratio"


class ConfidenceTier(str, Enum):
    """Confidence tier classification for inference rules and edges."""

    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"

    @classmethod
    def from_score(cls, score: float) -> ConfidenceTier:
        """Determines tier from confidence score."""
        if score >= 0.8:
            return cls.HIGH
        if score >= 0.5:
            return cls.MEDIUM
        return cls.LOW


@dataclass(frozen=True)
class EvidenceExtractionSpec:
    """Specification for extracting auditable evidence when a rule fires."""

    target_field: str = "combined"  # title, abstract, threat_model, combined
    max_snippet_length: int = 120
    case_sensitive: bool = False

    def to_dict(self) -> Dict[str, Any]:
        """Serializes spec to dictionary."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> EvidenceExtractionSpec:
        """Constructs EvidenceExtractionSpec from dictionary."""
        return cls(
            target_field=str(data.get("target_field", "combined")),
            max_snippet_length=int(data.get("max_snippet_length", 120)),
            case_sensitive=bool(data.get("case_sensitive", False)),
        )


def _validate_regex_safety(pattern_str: str) -> None:
    """Validates regex compilation and basic ReDoS resistance."""
    if REDOS_SUSPECT_PATTERN.search(pattern_str):
        raise ValueError(f"Suspect ReDoS pattern detected in regex: {pattern_str}")
    try:
        re.compile(pattern_str)
    except re.error as err:
        raise ValueError(f"Invalid regex pattern '{pattern_str}': {err}") from err


def _validate_confidence_bounds(confidence: float) -> None:
    """Ensures base_confidence is within [0.0, 1.0]."""
    if not (0.0 <= confidence <= 1.0):
        raise ValueError(f"Confidence score {confidence} must be within [0.0, 1.0]")


def _validate_rule_id(rule_id: str) -> None:
    """Validates rule_id prefix."""
    if not rule_id or not rule_id.startswith("RULE-"):
        raise ValueError(f"Invalid rule_id: '{rule_id}'. Must start with 'RULE-'.")


def _validate_labels(source_label: str, target_label: str, edge_label: str) -> None:
    """Validates non-empty vertex and edge labels."""
    if not source_label or not target_label or not edge_label:
        raise ValueError("source_label, target_label, and edge_label cannot be empty.")


def _validate_regex_condition(condition_spec: Dict[str, Any], rule_id: str) -> None:
    """Validates regex pattern condition."""
    pattern = str(condition_spec.get("pattern", ""))
    if not pattern:
        raise ValueError(f"Regex rule '{rule_id}' missing 'pattern' spec.")
    _validate_regex_safety(pattern)


@dataclass(frozen=True)
class EdgeInferenceRule:
    """
    Ontological axiom rule defining how vertices are linked via edges.
    """

    rule_id: str
    name: str
    description: str
    source_label: str
    target_label: str
    edge_label: str
    condition_type: RuleConditionType
    condition_spec: Dict[str, Any]
    base_confidence: float
    confidence_tier: ConfidenceTier
    evidence_spec: EvidenceExtractionSpec = field(
        default_factory=EvidenceExtractionSpec
    )
    version: str = "2026.09.1"
    is_active: bool = True

    def __post_init__(self) -> None:
        self.validate()

    def validate(self) -> None:
        """Validates rule invariants and condition parameters."""
        _validate_rule_id(self.rule_id)
        _validate_labels(self.source_label, self.target_label, self.edge_label)
        _validate_confidence_bounds(self.base_confidence)
        if self.condition_type == RuleConditionType.REGEX:
            _validate_regex_condition(self.condition_spec, self.rule_id)

    def to_dict(self) -> Dict[str, Any]:
        """Serializes rule to JSON-compatible dictionary."""
        return {
            "rule_id": self.rule_id,
            "name": self.name,
            "description": self.description,
            "source_label": self.source_label,
            "target_label": self.target_label,
            "edge_label": self.edge_label,
            "condition_type": self.condition_type.value,
            "condition_spec": self.condition_spec,
            "base_confidence": round(self.base_confidence, 4),
            "confidence_tier": self.confidence_tier.value,
            "evidence_spec": self.evidence_spec.to_dict(),
            "version": self.version,
            "is_active": self.is_active,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> EdgeInferenceRule:
        """Constructs EdgeInferenceRule from dictionary with validation."""
        cond_type_str = str(data.get("condition_type", "lexical"))
        tier_str = str(data.get("confidence_tier", "MEDIUM"))
        ev_spec_data = data.get("evidence_spec", {})

        return cls(
            rule_id=str(data.get("rule_id", "")),
            name=str(data.get("name", "")),
            description=str(data.get("description", "")),
            source_label=str(data.get("source_label", "")),
            target_label=str(data.get("target_label", "")),
            edge_label=str(data.get("edge_label", "")),
            condition_type=RuleConditionType(cond_type_str),
            condition_spec=dict(data.get("condition_spec", {})),
            base_confidence=float(data.get("base_confidence", 0.5)),
            confidence_tier=ConfidenceTier(tier_str),
            evidence_spec=EvidenceExtractionSpec.from_dict(ev_spec_data),
            version=str(data.get("version", "2026.09.1")),
            is_active=bool(data.get("is_active", True)),
        )
