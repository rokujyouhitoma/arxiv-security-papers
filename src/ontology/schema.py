#!/usr/bin/env python3
"""
Security Knowledge Ontology (SKO) Schema Definition.
Defines 7 Core Entities, 12 Relationship Predicates, and Triple structures.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, Dict, List, Set


class EntityType(str, Enum):
    """Enumeration of 7 Core Entity Types in Security Knowledge Ontology."""

    PAPER = "Paper"
    THREAT_ACTOR = "ThreatActor"
    ATTACK_TECHNIQUE = "AttackTechnique"
    VULNERABILITY = "Vulnerability"
    TARGET_ASSET = "TargetAsset"
    DEFENSE_MECHANISM = "DefenseMechanism"
    BENCHMARK_METRIC = "BenchmarkMetric"


class Predicate(str, Enum):
    """Enumeration of 12 Core Relationship Predicates in Security Knowledge Ontology."""

    DISCLOSES = "DISCLOSES"  # Paper -> Vulnerability
    EXPLOITS = "EXPLOITS"  # AttackTechnique -> Vulnerability
    ANALYZES = "ANALYZES"  # Paper -> AttackTechnique
    TARGETS = "TARGETS"  # AttackTechnique -> TargetAsset
    PROPOSES = "PROPOSES"  # Paper -> DefenseMechanism
    MITIGATES = "MITIGATES"  # DefenseMechanism -> AttackTechnique
    PATCHES = "PATCHES"  # DefenseMechanism -> Vulnerability
    EVALUATES = "EVALUATES"  # Paper -> BenchmarkMetric
    ATTRIBUTED_TO = "ATTRIBUTED_TO"  # AttackTechnique -> ThreatActor
    SUBCLASS_OF = "SUBCLASS_OF"  # Entity -> Entity (Taxonomy hierarchy)
    PART_OF = "PART_OF"  # TargetAsset -> TargetAsset
    CITES = "CITES"  # Paper -> Paper

    @property
    def inverse(self) -> str:
        """Returns the inverse predicate name."""
        inverse_map = {
            "DISCLOSES": "DISCLOSED_IN",
            "EXPLOITS": "EXPLOITED_BY",
            "ANALYZES": "ANALYZED_IN",
            "TARGETS": "TARGETED_BY",
            "PROPOSES": "PROPOSED_IN",
            "MITIGATES": "MITIGATED_BY",
            "PATCHES": "PATCHED_BY",
            "EVALUATES": "EVALUATED_IN",
            "ATTRIBUTED_TO": "EMPLOYS",
            "SUBCLASS_OF": "SUPERCLASS_OF",
            "PART_OF": "HAS_PART",
            "CITES": "CITED_BY",
        }
        return inverse_map.get(self.value, f"INVERSE_{self.value}")


@dataclass
class BaseEntity:
    """Base dataclass for all ontology entities."""

    id: str
    entity_type: EntityType
    name: str
    description: str = ""
    properties: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        data["entity_type"] = self.entity_type.value
        return data


@dataclass
class PaperEntity(BaseEntity):
    """Paper entity representing an arXiv research publication."""

    arxiv_id: str = ""
    title_ja: str = ""
    title_en: str = ""
    authors: List[str] = field(default_factory=list)
    published_at: str = ""
    credibility_score: float = 1.0

    def __post_init__(self) -> None:
        self.entity_type = EntityType.PAPER
        if not self.id:
            self.id = f"Paper:{self.arxiv_id}"
        if not self.name:
            self.name = self.title_ja or self.title_en or self.arxiv_id


@dataclass
class ThreatActorEntity(BaseEntity):
    """Threat Actor entity (e.g. APT28, Lazarus, Ransomware Group)."""

    actor_id: str = ""
    motivation: str = ""
    origin: str = ""

    def __post_init__(self) -> None:
        self.entity_type = EntityType.THREAT_ACTOR
        if not self.id:
            self.id = f"ThreatActor:{self.actor_id or self.name}"


@dataclass
class AttackTechniqueEntity(BaseEntity):
    """Attack Technique entity aligned with MITRE ATT&CK or emerging attack vectors."""

    technique_id: str = ""  # e.g. T1059 or Prompt_Injection
    tactic: str = ""  # Initial Access, Execution, etc.
    abstraction_level: str = "Technique"  # Tactic, Technique, Sub-technique

    def __post_init__(self) -> None:
        self.entity_type = EntityType.ATTACK_TECHNIQUE
        if not self.id:
            self.id = f"AttackTechnique:{self.technique_id or self.name}"


@dataclass
class VulnerabilityEntity(BaseEntity):
    """Vulnerability entity aligned with CWE (Common Weakness Enumeration) or CVE."""

    cwe_id: str = ""  # e.g. CWE-79, CWE-94
    cve_id: str = ""  # e.g. CVE-2024-XXXX
    severity: str = "Medium"  # Critical, High, Medium, Low

    def __post_init__(self) -> None:
        self.entity_type = EntityType.VULNERABILITY
        if not self.id:
            self.id = f"Vulnerability:{self.cwe_id or self.cve_id or self.name}"


@dataclass
class TargetAssetEntity(BaseEntity):
    """Target Asset entity representing system, architecture, or software under attack."""

    asset_type: str = ""  # LLM, Firmware, SmartContract, Cloud, CPU
    architecture: str = ""  # ARM, RISC-V, Transformer, EVM

    def __post_init__(self) -> None:
        self.entity_type = EntityType.TARGET_ASSET
        if not self.id:
            self.id = f"TargetAsset:{self.asset_type or self.name}"


@dataclass
class DefenseMechanismEntity(BaseEntity):
    """Defense Mechanism entity representing countermeasures, mitigations, or security controls."""

    defense_id: str = ""
    category: str = ""  # ZKP, Sandbox, Filter, DP, Formal Verification
    nist_sp800_control: str = ""  # e.g. AC-3, SI-10

    def __post_init__(self) -> None:
        self.entity_type = EntityType.DEFENSE_MECHANISM
        if not self.id:
            self.id = f"DefenseMechanism:{self.defense_id or self.name}"


@dataclass
class BenchmarkMetricEntity(BaseEntity):
    """Benchmark Metric entity representing quantitative experimental evaluation results."""

    metric_id: str = ""
    metric_name: str = ""  # ASR (Attack Success Rate), Overhead %, F1-Score
    value: float = 0.0
    unit: str = "%"

    def __post_init__(self) -> None:
        self.entity_type = EntityType.BENCHMARK_METRIC
        if not self.id:
            self.id = f"BenchmarkMetric:{self.metric_id or self.name}"


@dataclass(frozen=True)
class Triple:
    """Represents a factual Semantic Knowledge Graph Triple (Subject - Predicate - Object)."""

    subject_id: str
    predicate: Predicate
    object_id: str
    weight: float = 1.0
    properties: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "subject": self.subject_id,
            "predicate": self.predicate.value,
            "object": self.object_id,
            "weight": self.weight,
            "properties": self.properties,
        }


class SecurityOntologySchema:
    """
    Schema validator enforcing domain constraints on entities and relationships.
    """

    ALLOWED_RELATIONS: Dict[EntityType, Set[Predicate]] = {
        EntityType.PAPER: {
            Predicate.DISCLOSES,
            Predicate.ANALYZES,
            Predicate.PROPOSES,
            Predicate.EVALUATES,
            Predicate.CITES,
        },
        EntityType.ATTACK_TECHNIQUE: {
            Predicate.EXPLOITS,
            Predicate.TARGETS,
            Predicate.ATTRIBUTED_TO,
            Predicate.SUBCLASS_OF,
        },
        EntityType.DEFENSE_MECHANISM: {
            Predicate.MITIGATES,
            Predicate.PATCHES,
            Predicate.SUBCLASS_OF,
        },
        EntityType.TARGET_ASSET: {
            Predicate.PART_OF,
            Predicate.SUBCLASS_OF,
        },
    }

    @classmethod
    def validate_triple(cls, src_type: EntityType, predicate: Predicate) -> bool:
        """Validates whether a predicate is logically permissible from src_type."""
        allowed = cls.ALLOWED_RELATIONS.get(src_type, set())
        return predicate in allowed
