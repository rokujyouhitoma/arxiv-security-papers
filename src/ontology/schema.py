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
    """Enumeration of Core Entity Types in Security Knowledge Ontology."""

    PAPER = "Paper"
    THREAT_ACTOR = "ThreatActor"
    ATTACK_TECHNIQUE = "AttackTechnique"
    VULNERABILITY = "Vulnerability"
    TARGET_ASSET = "TargetAsset"
    DEFENSE_MECHANISM = "DefenseMechanism"
    BENCHMARK_METRIC = "BenchmarkMetric"
    # Full-Spectrum SKO Extensions (Issue #179)
    INCIDENT = "Incident"
    DETECTION_RULE = "DetectionRule"
    POC_ARTIFACT = "PoCArtifact"
    PRECONDITION = "Precondition"
    RESEARCH_GAP = "ResearchGap"
    RESIDUAL_RISK = "ResidualRisk"
    PUBLICATION_VENUE = "PublicationVenue"
    # Causal & Reified Extensions (Issue #185, #186, #188)
    IMPACT = "Impact"
    CLAIM = "Claim"
    EVALUATION_RESULT = "EvaluationResult"


class Predicate(str, Enum):
    """Enumeration of Relationship Predicates in Security Knowledge Ontology."""

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
    # Full-Spectrum SKO Extensions (Issue #179)
    BLOCKS = "BLOCKS"  # DetectionRule -> AttackTechnique
    GENERATES_RULE = "GENERATES_RULE"  # DefenseMechanism -> DetectionRule
    REQUIRES_PRECONDITION = "REQUIRES_PRECONDITION"  # AttackTechnique -> Precondition
    LEAVES_UNADDRESSED = "LEAVES_UNADDRESSED"  # DefenseMechanism -> ResidualRisk
    IDENTIFIES_GAP = "IDENTIFIES_GAP"  # Paper -> ResearchGap
    PRESENTED_AT = "PRESENTED_AT"  # Paper -> PublicationVenue
    VERIFIES_CVE = "VERIFIES_CVE"  # Paper -> Vulnerability
    HAS_POC = "HAS_POC"  # Paper -> PoCArtifact
    # Causal & Reified Predicates (Issue #185, #186, #188)
    HAS_IMPACT = "HAS_IMPACT"  # AttackTechnique -> Impact
    NEUTRALIZES_PRECONDITION = (
        "NEUTRALIZES_PRECONDITION"  # DefenseMechanism -> Precondition
    )
    EXPLOITED_IN = "EXPLOITED_IN"  # AttackTechnique -> Incident
    LEVERAGED_VULNERABILITY = "LEVERAGED_VULNERABILITY"  # Incident -> Vulnerability
    ASSERTS_CLAIM = "ASSERTS_CLAIM"  # Paper -> Claim
    EVALUATES_TECHNIQUE = "EVALUATES_TECHNIQUE"  # EvaluationResult -> AttackTechnique
    EVALUATES_CLAIM = "EVALUATES_CLAIM"  # EvaluationResult -> Claim
    YIELDS_EVALUATION = "YIELDS_EVALUATION"  # Paper -> EvaluationResult

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
            "BLOCKS": "BLOCKED_BY",
            "GENERATES_RULE": "GENERATED_FROM",
            "REQUIRES_PRECONDITION": "PRECONDITION_FOR",
            "LEAVES_UNADDRESSED": "UNADDRESSED_IN",
            "IDENTIFIES_GAP": "IDENTIFIED_IN",
            "PRESENTED_AT": "HOSTED_PAPER",
            "VERIFIES_CVE": "VERIFIED_IN",
            "HAS_POC": "POC_OF",
            "HAS_IMPACT": "IMPACT_CAUSED_BY",
            "NEUTRALIZES_PRECONDITION": "PRECONDITION_NEUTRALIZED_BY",
            "EXPLOITED_IN": "OBSERVED_TECHNIQUE",
            "LEVERAGED_VULNERABILITY": "EXPLOITED_IN_INCIDENT",
            "ASSERTS_CLAIM": "CLAIM_ASSERTED_BY",
            "EVALUATES_TECHNIQUE": "TECHNIQUE_EVALUATED_IN",
            "EVALUATES_CLAIM": "CLAIM_EVALUATED_IN",
            "YIELDS_EVALUATION": "EVALUATION_YIELDED_BY",
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

    def _resolve_name(self) -> str:
        """Determines display name for paper entity."""
        if self.title_ja:
            return self.title_ja
        if self.title_en:
            return self.title_en
        return self.arxiv_id

    def __post_init__(self) -> None:
        self.entity_type = EntityType.PAPER
        if not self.id:
            self.id = f"Paper:{self.arxiv_id}"
        if not self.name:
            self.name = self._resolve_name()


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


@dataclass
class IncidentEntity(BaseEntity):
    """Incident entity representing observed real-world attack occurrences."""

    incident_id: str = ""
    occurred_at: str = ""
    severity: str = "High"

    def __post_init__(self) -> None:
        self.entity_type = EntityType.INCIDENT
        if not self.id:
            self.id = f"Incident:{self.incident_id or self.name}"


@dataclass
class DetectionRuleEntity(BaseEntity):
    """Detection Rule entity representing actionable defense code (Semgrep, Sigma, YARA)."""

    rule_id: str = ""
    rule_format: str = "semgrep"  # semgrep, sigma, yara
    rule_content: str = ""
    target_technique: str = ""

    def __post_init__(self) -> None:
        self.entity_type = EntityType.DETECTION_RULE
        if not self.id:
            self.id = f"DetectionRule:{self.rule_id or self.name}"


@dataclass
class PoCArtifactEntity(BaseEntity):
    """PoC Artifact entity representing software code, repositories, or artifacts."""

    artifact_id: str = ""
    repo_url: str = ""
    artifact_type: str = "github"  # github, docker, script

    def __post_init__(self) -> None:
        self.entity_type = EntityType.POC_ARTIFACT
        if not self.id:
            self.id = f"PoCArtifact:{self.artifact_id or self.name}"


@dataclass
class PreconditionEntity(BaseEntity):
    """Precondition entity representing threat model assumptions and access requirements."""

    precondition_id: str = ""
    access_level: str = "Remote"  # Remote, Local, Physical, Admin
    assumed_knowledge: str = "Black-box"  # White-box, Gray-box, Black-box

    def __post_init__(self) -> None:
        self.entity_type = EntityType.PRECONDITION
        if not self.id:
            self.id = f"Precondition:{self.precondition_id or self.name}"


@dataclass
class ResearchGapEntity(BaseEntity):
    """Research Gap entity representing unaddressed limitations and future challenges."""

    gap_id: str = ""
    domain: str = ""

    def __post_init__(self) -> None:
        self.entity_type = EntityType.RESEARCH_GAP
        if not self.id:
            self.id = f"ResearchGap:{self.gap_id or self.name}"


@dataclass
class ResidualRiskEntity(BaseEntity):
    """Residual Risk entity representing remaining blind spots after defenses are applied."""

    risk_id: str = ""
    bypass_vector: str = ""

    def __post_init__(self) -> None:
        self.entity_type = EntityType.RESIDUAL_RISK
        if not self.id:
            self.id = f"ResidualRisk:{self.risk_id or self.name}"


@dataclass
class PublicationVenueEntity(BaseEntity):
    """Publication Venue entity representing top academic conferences or journals."""

    venue_id: str = ""
    tier: str = "Tier-1"  # Tier-1 (IEEE S&P, USENIX, CCS, NDSS), Preprint (arXiv)

    def __post_init__(self) -> None:
        self.entity_type = EntityType.PUBLICATION_VENUE
        if not self.id:
            self.id = f"PublicationVenue:{self.venue_id or self.name}"


@dataclass
class ImpactEntity(BaseEntity):
    """Impact entity representing consequences and STRIDE threat impacts."""

    impact_id: str = ""
    stride_category: str = (
        "Tampering"  # Spoofing, Tampering, Repudiation, InformationDisclosure, DenialOfService, ElevationOfPrivilege
    )
    severity: str = "High"  # Low, Medium, High, Critical

    def __post_init__(self) -> None:
        self.entity_type = EntityType.IMPACT
        if not self.id:
            self.id = f"Impact:{self.impact_id or self.name}"


@dataclass
class ClaimEntity(BaseEntity):
    """Claim entity representing an academic research proposition or security assertion."""

    claim_id: str = ""
    target_technique: str = ""
    claim_type: str = (
        "DefenseEfficacy"  # AttackDiscovery, DefenseEfficacy, VulnerabilityProof
    )

    def __post_init__(self) -> None:
        self.entity_type = EntityType.CLAIM
        if not self.id:
            self.id = f"Claim:{self.claim_id or self.name}"


@dataclass
class EvaluationResultEntity(BaseEntity):
    """EvaluationResult entity reifying experimental metrics and execution environments."""

    evaluation_id: str = ""
    metric_name: str = "Accuracy"
    value: float = 0.0
    success_rate: float = 0.0
    target_environment: str = "Linux/Cloud"

    def __post_init__(self) -> None:
        self.entity_type = EntityType.EVALUATION_RESULT
        if not self.id:
            self.id = f"EvaluationResult:{self.evaluation_id or self.name}"


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
    """Schema validator enforcing domain constraints on entities and relationships."""

    ALLOWED_RELATIONS: Dict[EntityType, Set[Predicate]] = {
        EntityType.PAPER: {
            Predicate.DISCLOSES,
            Predicate.ANALYZES,
            Predicate.PROPOSES,
            Predicate.EVALUATES,
            Predicate.CITES,
            Predicate.IDENTIFIES_GAP,
            Predicate.PRESENTED_AT,
            Predicate.VERIFIES_CVE,
            Predicate.HAS_POC,
            Predicate.REQUIRES_PRECONDITION,
            Predicate.LEAVES_UNADDRESSED,
            Predicate.GENERATES_RULE,
            Predicate.ASSERTS_CLAIM,
            Predicate.YIELDS_EVALUATION,
            Predicate.HAS_IMPACT,
            Predicate.NEUTRALIZES_PRECONDITION,
        },
        EntityType.ATTACK_TECHNIQUE: {
            Predicate.EXPLOITS,
            Predicate.TARGETS,
            Predicate.ATTRIBUTED_TO,
            Predicate.SUBCLASS_OF,
            Predicate.REQUIRES_PRECONDITION,
            Predicate.HAS_IMPACT,
            Predicate.EXPLOITED_IN,
        },
        EntityType.DEFENSE_MECHANISM: {
            Predicate.MITIGATES,
            Predicate.PATCHES,
            Predicate.SUBCLASS_OF,
            Predicate.GENERATES_RULE,
            Predicate.LEAVES_UNADDRESSED,
            Predicate.NEUTRALIZES_PRECONDITION,
        },
        EntityType.TARGET_ASSET: {
            Predicate.PART_OF,
            Predicate.SUBCLASS_OF,
        },
        EntityType.DETECTION_RULE: {
            Predicate.BLOCKS,
            Predicate.SUBCLASS_OF,
        },
        EntityType.THREAT_ACTOR: {
            Predicate.SUBCLASS_OF,
        },
        EntityType.INCIDENT: {
            Predicate.SUBCLASS_OF,
            Predicate.LEVERAGED_VULNERABILITY,
        },
        EntityType.CLAIM: {
            Predicate.SUBCLASS_OF,
        },
        EntityType.EVALUATION_RESULT: {
            Predicate.EVALUATES_CLAIM,
            Predicate.EVALUATES_TECHNIQUE,
            Predicate.SUBCLASS_OF,
        },
        EntityType.IMPACT: {
            Predicate.SUBCLASS_OF,
        },
    }

    @classmethod
    def validate_triple(cls, src_type: EntityType, predicate: Predicate) -> bool:
        """Validates whether a predicate is logically permissible from src_type."""
        allowed = cls.ALLOWED_RELATIONS.get(src_type, set())
        return predicate in allowed
