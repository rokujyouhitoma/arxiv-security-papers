#!/usr/bin/env python3
"""
Security Knowledge Ontology (SKO) Schema Definition.
Defines 7 Core Entities, 12 Relationship Predicates, and Triple structures.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple


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


@dataclass(frozen=True)
class EntityTypeSpec:
    """Specification of entity type semantics in Security Knowledge Ontology (TBox)."""

    entity_type: EntityType
    uri: str
    label_ja: str
    description_ja: str = ""
    section_comment: Optional[str] = None


@dataclass(frozen=True)
class PredicateSpec:
    """Specification of relationship predicate semantics in Security Knowledge Ontology (TBox)."""

    predicate: Predicate
    uri: str
    label_ja: str
    description_ja: str = ""
    domain: EntityType = EntityType.PAPER
    range: EntityType = EntityType.PAPER
    allowed_domains: Tuple[EntityType, ...] = ()
    allowed_ranges: Tuple[EntityType, ...] = ()
    inverse_predicate_name: Optional[str] = None
    inverse_uri: Optional[str] = None
    inverse_label_ja: Optional[str] = None
    is_transitive: bool = False
    sub_property_of: Optional[str] = None
    section_comment: Optional[str] = None


@dataclass(frozen=True)
class ObjectPropertySpec:
    """Specification of standalone RDF/OWL object property semantics."""

    uri: str
    label_ja: str
    domain_uri: str
    range_uri: str
    description_ja: str = ""
    inverse_uri: Optional[str] = None
    inverse_label_ja: Optional[str] = None
    is_transitive: bool = False
    sub_property_of: Optional[str] = None
    section_comment: Optional[str] = None


ENTITY_TYPE_SPECS: Dict[EntityType, EntityTypeSpec] = {
    EntityType.PAPER: EntityTypeSpec(
        entity_type=EntityType.PAPER,
        uri="sec:Paper",
        label_ja="セキュリティ論文",
        description_ja="arXiv または IACR 等で公開された学術セキュリティ論文",
        section_comment="学術知見実体",
    ),
    EntityType.THREAT_ACTOR: EntityTypeSpec(
        entity_type=EntityType.THREAT_ACTOR,
        uri="sec:ThreatActor",
        label_ja="脅威アクター",
        description_ja="サイバー攻撃を仕掛ける国家主導組織、APTグループ、または脅威主体",
        section_comment="脅威・インテリジェンス実体",
    ),
    EntityType.ATTACK_TECHNIQUE: EntityTypeSpec(
        entity_type=EntityType.ATTACK_TECHNIQUE,
        uri="sec:AttackTechnique",
        label_ja="攻撃手法",
        description_ja="MITRE ATT&CK または学術知見で定義される戦術・技術・手順 (TTP)",
    ),
    EntityType.VULNERABILITY: EntityTypeSpec(
        entity_type=EntityType.VULNERABILITY,
        uri="sec:Vulnerability",
        label_ja="脆弱性",
        description_ja="CWE または CVE で特定されるソフトウェア/システムの弱点およびセキュリティ欠陥",
    ),
    EntityType.TARGET_ASSET: EntityTypeSpec(
        entity_type=EntityType.TARGET_ASSET,
        uri="sec:TargetAsset",
        label_ja="対象資産",
        description_ja="攻撃の標的となるシステム、プロトコル、ハードウェア、またはAIモデル",
    ),
    EntityType.DEFENSE_MECHANISM: EntityTypeSpec(
        entity_type=EntityType.DEFENSE_MECHANISM,
        uri="sec:DefenseMechanism",
        label_ja="防御メカニズム",
        description_ja="論文で提案される防御機構、緩和策、またはセキュアシグネチャ",
    ),
    EntityType.BENCHMARK_METRIC: EntityTypeSpec(
        entity_type=EntityType.BENCHMARK_METRIC,
        uri="sec:BenchmarkMetric",
        label_ja="評価ベンチマーク指標",
        description_ja="防御性能や攻撃成功率を測定するための客観的メトリクス",
    ),
    EntityType.INCIDENT: EntityTypeSpec(
        entity_type=EntityType.INCIDENT,
        uri="sec:Incident",
        label_ja="実世界インシデント",
        description_ja="観測された実世界での侵害事例およびセキュリティインシデント",
        section_comment="実世界脅威事象",
    ),
    EntityType.DETECTION_RULE: EntityTypeSpec(
        entity_type=EntityType.DETECTION_RULE,
        uri="sec:DetectionRule",
        label_ja="検知・防御ルール",
        description_ja="Semgrep, Sigma, YARA などの機械可読な防御シグネチャコード",
        section_comment="即応防御成果物",
    ),
    EntityType.POC_ARTIFACT: EntityTypeSpec(
        entity_type=EntityType.POC_ARTIFACT,
        uri="sec:PoCArtifact",
        label_ja="PoCソフトウェア成果物",
        description_ja="GitHub リポジトリや Dockerfile などの実証ソフトウェアコード",
    ),
    EntityType.PRECONDITION: EntityTypeSpec(
        entity_type=EntityType.PRECONDITION,
        uri="sec:Precondition",
        label_ja="成立前提条件・脅威モデル",
        description_ja="攻撃や防御が成立するために必要なアクセス権限や知識モデル要件",
        section_comment="成立前提・制約境界",
    ),
    EntityType.IMPACT: EntityTypeSpec(
        entity_type=EntityType.IMPACT,
        uri="sec:Impact",
        label_ja="被害影響・影響度",
        description_ja="攻撃成立により発生する機密性/完全性/可用性の侵害または権限昇格等の結果事象 (STRIDE/CIA侵害)",
        section_comment="脅威被害・結果影響",
    ),
    EntityType.RESEARCH_GAP: EntityTypeSpec(
        entity_type=EntityType.RESEARCH_GAP,
        uri="sec:ResearchGap",
        label_ja="未解決研究課題",
        description_ja="学術的・技術的に未解決の限界および将来の探究テーマ",
        section_comment="研究限界・未解決課題",
    ),
    EntityType.RESIDUAL_RISK: EntityTypeSpec(
        entity_type=EntityType.RESIDUAL_RISK,
        uri="sec:ResidualRisk",
        label_ja="残余リスク・死角",
        description_ja="防御策適用後もなお残存するバイパス手法や潜在的脅威",
    ),
    EntityType.PUBLICATION_VENUE: EntityTypeSpec(
        entity_type=EntityType.PUBLICATION_VENUE,
        uri="sec:PublicationVenue",
        label_ja="採択会議・出版媒体",
        description_ja="IEEE S&P, USENIX, CCS, NDSS などの学術トップカンファレンス",
        section_comment="学術来歴・信頼性",
    ),
    EntityType.CLAIM: EntityTypeSpec(
        entity_type=EntityType.CLAIM,
        uri="sec:Claim",
        label_ja="学術的主張・命題",
        description_ja="論文著者が提唱・主張する防御性能や緩和効果の命題",
        section_comment="学術的主張（著者主張）",
    ),
    EntityType.EVALUATION_RESULT: EntityTypeSpec(
        entity_type=EntityType.EVALUATION_RESULT,
        uri="sec:EvaluationResult",
        label_ja="実証評価イベント・検証事実",
        description_ja="独立した第三者や実験環境における客観的ベンチマーク・再現性評価イベント（関係性の具現化ノード）",
        section_comment="実証事実・エッジ属性保持実体",
    ),
}

PREDICATE_SPECS: Dict[Predicate, PredicateSpec] = {
    Predicate.DISCLOSES: PredicateSpec(
        predicate=Predicate.DISCLOSES,
        uri="sec:discloses",
        label_ja="脆弱性を公開・開示する",
        description_ja="論文が新規または既存の脆弱性を開示・発表する関係",
        domain=EntityType.PAPER,
        range=EntityType.VULNERABILITY,
        inverse_predicate_name="DISCLOSED_IN",
        inverse_uri="sec:disclosedIn",
        inverse_label_ja="論文で公開・開示された",
        section_comment="論文と脆弱性の関係",
    ),
    Predicate.EXPLOITS: PredicateSpec(
        predicate=Predicate.EXPLOITS,
        uri="sec:exploits",
        label_ja="脆弱性を悪用する",
        description_ja="攻撃手法が特定の脆弱性を悪用・侵害する関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.VULNERABILITY,
        inverse_predicate_name="EXPLOITED_BY",
        inverse_uri="sec:exploitedBy",
        inverse_label_ja="攻撃手法により悪用される",
        section_comment="攻撃手法と脆弱性の関係",
    ),
    Predicate.ANALYZES: PredicateSpec(
        predicate=Predicate.ANALYZES,
        uri="sec:analyzes",
        label_ja="攻撃手法を分析する",
        description_ja="論文が攻撃手法・TTPを理論的または実験的に分析する関係",
        domain=EntityType.PAPER,
        range=EntityType.ATTACK_TECHNIQUE,
        inverse_predicate_name="ANALYZED_IN",
        inverse_uri="sec:analyzedIn",
        inverse_label_ja="論文で分析・解明された",
        section_comment="論文と攻撃手法の関係",
    ),
    Predicate.TARGETS: PredicateSpec(
        predicate=Predicate.TARGETS,
        uri="sec:targets",
        label_ja="資産を標的とする",
        description_ja="攻撃手法が特定のシステム・資産を侵害標的とする関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.TARGET_ASSET,
        inverse_predicate_name="TARGETED_BY",
        inverse_uri="sec:targetedBy",
        inverse_label_ja="攻撃手法の標的となる",
        section_comment="攻撃手法と対象資産の関係",
    ),
    Predicate.PROPOSES: PredicateSpec(
        predicate=Predicate.PROPOSES,
        uri="sec:proposes",
        label_ja="防御策を提案する",
        description_ja="論文が新規防御機構・緩和策を提案する関係",
        domain=EntityType.PAPER,
        range=EntityType.DEFENSE_MECHANISM,
        inverse_predicate_name="PROPOSED_IN",
        inverse_uri="sec:proposedIn",
        inverse_label_ja="論文で提案された",
        section_comment="論文と防御メカニズムの関係",
    ),
    Predicate.MITIGATES: PredicateSpec(
        predicate=Predicate.MITIGATES,
        uri="sec:mitigates",
        label_ja="攻撃手法を緩和・防御する",
        description_ja="防御策が攻撃手法の影響を低減・遮断する関係",
        domain=EntityType.DEFENSE_MECHANISM,
        range=EntityType.ATTACK_TECHNIQUE,
        inverse_predicate_name="MITIGATED_BY",
        inverse_uri="sec:mitigatedBy",
        inverse_label_ja="攻撃手法が緩和・防御される",
        section_comment="防御策と攻撃手法の関係",
    ),
    Predicate.PATCHES: PredicateSpec(
        predicate=Predicate.PATCHES,
        uri="sec:patches",
        label_ja="脆弱性を改修・修復する",
        description_ja="防御策がソフトウェア等の脆弱性を直接修正・無効化する関係",
        domain=EntityType.DEFENSE_MECHANISM,
        range=EntityType.VULNERABILITY,
        inverse_predicate_name="PATCHED_BY",
        inverse_uri="sec:patchedBy",
        inverse_label_ja="脆弱性が改修・修復される",
        section_comment="防御策と脆弱性の関係",
    ),
    Predicate.EVALUATES: PredicateSpec(
        predicate=Predicate.EVALUATES,
        uri="sec:evaluates",
        label_ja="評価指標で測定する",
        description_ja="論文が客観的ベンチマーク指標で有効性を評価する関係",
        domain=EntityType.PAPER,
        range=EntityType.BENCHMARK_METRIC,
        inverse_predicate_name="EVALUATED_IN",
        inverse_uri="sec:evaluatedIn",
        inverse_label_ja="論文で評価・測定された",
        section_comment="論文と評価指標の関係",
    ),
    Predicate.ATTRIBUTED_TO: PredicateSpec(
        predicate=Predicate.ATTRIBUTED_TO,
        uri="sec:attributedTo",
        label_ja="脅威アクターに帰属する",
        description_ja="攻撃手法が特定の脅威アクターやAPTグループに帰属する関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.THREAT_ACTOR,
        inverse_predicate_name="EMPLOYS",
        inverse_uri="sec:actorAttributedTechnique",
        inverse_label_ja="脅威アクターが使用する攻撃手法",
        section_comment="攻撃手法と脅威アクターの関係",
    ),
    Predicate.SUBCLASS_OF: PredicateSpec(
        predicate=Predicate.SUBCLASS_OF,
        uri="rdfs:subClassOf",
        label_ja="下位クラスである",
        description_ja="オントロジーのタクソノミ階層関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.ATTACK_TECHNIQUE,
        allowed_domains=tuple(EntityType),
        allowed_ranges=tuple(EntityType),
        inverse_predicate_name="SUPERCLASS_OF",
    ),
    Predicate.PART_OF: PredicateSpec(
        predicate=Predicate.PART_OF,
        uri="sec:partOf",
        label_ja="構成要素である",
        description_ja="資産間の部分-全体包含関係",
        domain=EntityType.TARGET_ASSET,
        range=EntityType.TARGET_ASSET,
        inverse_predicate_name="HAS_PART",
        inverse_uri="sec:hasPart",
        inverse_label_ja="構成要素として含む",
        section_comment="対象資産の包含関係",
    ),
    Predicate.CITES: PredicateSpec(
        predicate=Predicate.CITES,
        uri="sec:cites",
        label_ja="先行研究を引用する",
        description_ja="論文間の先行研究引用関係（CiTO cito:cites アライメント）",
        domain=EntityType.PAPER,
        range=EntityType.PAPER,
        inverse_predicate_name="CITED_BY",
        sub_property_of="cito:cites",
        section_comment="論文間の引用関係（CiTOアライメント・直接引用）",
    ),
    Predicate.BLOCKS: PredicateSpec(
        predicate=Predicate.BLOCKS,
        uri="sec:blocks",
        label_ja="攻撃手法を検知・遮断する",
        description_ja="検知ルールが攻撃手法の実行を遮断・警告する関係",
        domain=EntityType.DETECTION_RULE,
        range=EntityType.ATTACK_TECHNIQUE,
        inverse_predicate_name="BLOCKED_BY",
        inverse_uri="sec:blockedBy",
        inverse_label_ja="検知ルールにより検知・遮断される",
        section_comment="検知ルールと攻撃手法の関係",
    ),
    Predicate.GENERATES_RULE: PredicateSpec(
        predicate=Predicate.GENERATES_RULE,
        uri="sec:generatesRule",
        label_ja="防御シグネチャを生成する",
        description_ja="防御策から機械可読な検知シグネチャを導出・生成する関係",
        domain=EntityType.DEFENSE_MECHANISM,
        range=EntityType.DETECTION_RULE,
        allowed_domains=(EntityType.DEFENSE_MECHANISM, EntityType.PAPER),
        inverse_predicate_name="GENERATED_FROM",
        inverse_uri="sec:ruleGeneratedBy",
        inverse_label_ja="防御策から生成されたシグネチャ",
        section_comment="防御策と検知ルールの関係",
    ),
    Predicate.REQUIRES_PRECONDITION: PredicateSpec(
        predicate=Predicate.REQUIRES_PRECONDITION,
        uri="sec:requiresPrecondition",
        label_ja="成立前提条件を要求する",
        description_ja="攻撃手法または検証の成立に特定の前提条件・アクセス権限を要する関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.PRECONDITION,
        allowed_domains=(EntityType.ATTACK_TECHNIQUE, EntityType.PAPER),
        inverse_predicate_name="PRECONDITION_FOR",
        inverse_uri="sec:preconditionRequiredBy",
        inverse_label_ja="前提条件を要求する攻撃手法",
        section_comment="攻撃手法と前提条件の関係",
    ),
    Predicate.LEAVES_UNADDRESSED: PredicateSpec(
        predicate=Predicate.LEAVES_UNADDRESSED,
        uri="sec:leavesUnaddressed",
        label_ja="残余リスクを未対処とする",
        description_ja="防御策の適用後もなお未解決のまま残存するリスク",
        domain=EntityType.DEFENSE_MECHANISM,
        range=EntityType.RESIDUAL_RISK,
        allowed_domains=(EntityType.DEFENSE_MECHANISM, EntityType.PAPER),
        inverse_predicate_name="UNADDRESSED_IN",
        inverse_uri="sec:unaddressedBy",
        inverse_label_ja="防御策で未対処として残存する",
        section_comment="防御策と残余リスクの関係",
    ),
    Predicate.IDENTIFIES_GAP: PredicateSpec(
        predicate=Predicate.IDENTIFIES_GAP,
        uri="sec:identifiesGap",
        label_ja="未解決課題を提起・特定する",
        description_ja="論文が将来の研究課題・学術的限界を特定する関係",
        domain=EntityType.PAPER,
        range=EntityType.RESEARCH_GAP,
        inverse_predicate_name="IDENTIFIED_IN",
        inverse_uri="sec:gapIdentifiedBy",
        inverse_label_ja="論文により特定された未解決課題",
        section_comment="論文と研究ギャップの関係",
    ),
    Predicate.PRESENTED_AT: PredicateSpec(
        predicate=Predicate.PRESENTED_AT,
        uri="sec:presentedAt",
        label_ja="採択・発表される",
        description_ja="論文が国際会議や学術雑誌で採択・発表された関係",
        domain=EntityType.PAPER,
        range=EntityType.PUBLICATION_VENUE,
        inverse_predicate_name="HOSTED_PAPER",
        inverse_uri="sec:venuePresentedPaper",
        inverse_label_ja="採択・発表された論文",
        section_comment="論文と発表媒体の関係",
    ),
    Predicate.VERIFIES_CVE: PredicateSpec(
        predicate=Predicate.VERIFIES_CVE,
        uri="sec:verifiesCVE",
        label_ja="既知脆弱性を検証・悪用実証する",
        description_ja="論文が既知のCVE脆弱性に対して実証的攻撃または検証を行う関係",
        domain=EntityType.PAPER,
        range=EntityType.VULNERABILITY,
        inverse_predicate_name="VERIFIED_IN",
        inverse_uri="sec:cveVerifiedBy",
        inverse_label_ja="論文により悪用実証された脆弱性",
        section_comment="論文と既知脆弱性の実証関係",
    ),
    Predicate.HAS_POC: PredicateSpec(
        predicate=Predicate.HAS_POC,
        uri="sec:hasPoC",
        label_ja="PoC成果物を有する",
        description_ja="論文が公開PoCコードやソフトウェアリポジトリを伴う関係",
        domain=EntityType.PAPER,
        range=EntityType.POC_ARTIFACT,
        inverse_predicate_name="POC_OF",
        inverse_uri="sec:pocOfPaper",
        inverse_label_ja="論文のPoC成果物",
        section_comment="論文とPoCコードの関係",
    ),
    Predicate.HAS_IMPACT: PredicateSpec(
        predicate=Predicate.HAS_IMPACT,
        uri="sec:hasImpact",
        label_ja="被害影響をもたらす",
        description_ja="攻撃手法がCIA侵害や権限昇格などの被害影響を及ぼす因果関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.IMPACT,
        allowed_domains=(EntityType.ATTACK_TECHNIQUE, EntityType.PAPER),
        inverse_predicate_name="IMPACT_CAUSED_BY",
        inverse_uri="sec:impactCausedBy",
        inverse_label_ja="被害影響をもたらした攻撃手法",
        section_comment="攻撃手法と被害影響（STRIDE/CIA侵害）の因果関係",
    ),
    Predicate.NEUTRALIZES_PRECONDITION: PredicateSpec(
        predicate=Predicate.NEUTRALIZES_PRECONDITION,
        uri="sec:neutralizesPrecondition",
        label_ja="攻撃前提条件を無力化・打破する",
        description_ja="防御策が攻撃成立に必要な前提条件を無効化する因果関係",
        domain=EntityType.DEFENSE_MECHANISM,
        range=EntityType.PRECONDITION,
        allowed_domains=(EntityType.DEFENSE_MECHANISM, EntityType.PAPER),
        inverse_predicate_name="PRECONDITION_NEUTRALIZED_BY",
        inverse_uri="sec:preconditionNeutralizedBy",
        inverse_label_ja="防御策により無力化される前提条件",
        section_comment="防御策による攻撃成立前提条件の無力化因果関係",
    ),
    Predicate.EXPLOITED_IN: PredicateSpec(
        predicate=Predicate.EXPLOITED_IN,
        uri="sec:exploitedIn",
        label_ja="インシデントで悪用が観測された",
        description_ja="攻撃手法が実世界のインシデント事例で悪用・観測された関係",
        domain=EntityType.ATTACK_TECHNIQUE,
        range=EntityType.INCIDENT,
        inverse_predicate_name="OBSERVED_TECHNIQUE",
        inverse_uri="sec:incidentObservedTechnique",
        inverse_label_ja="インシデントで観測された攻撃手法",
        section_comment="攻撃手法とインシデントの関係",
    ),
    Predicate.LEVERAGED_VULNERABILITY: PredicateSpec(
        predicate=Predicate.LEVERAGED_VULNERABILITY,
        uri="sec:leveragedVulnerability",
        label_ja="インシデントで悪用された脆弱性",
        description_ja="実世界インシデントで侵害契機となった脆弱性の関係",
        domain=EntityType.INCIDENT,
        range=EntityType.VULNERABILITY,
        inverse_predicate_name="EXPLOITED_IN_INCIDENT",
        inverse_uri="sec:vulnerabilityLeveragedIn",
        inverse_label_ja="脆弱性が悪用されたインシデント",
        section_comment="インシデントと脆弱性の関係",
    ),
    Predicate.ASSERTS_CLAIM: PredicateSpec(
        predicate=Predicate.ASSERTS_CLAIM,
        uri="sec:assertsClaim",
        label_ja="命題を主張する",
        description_ja="論文著者が防御性能や緩和効果の命題を主張する関係",
        domain=EntityType.PAPER,
        range=EntityType.CLAIM,
        inverse_predicate_name="CLAIM_ASSERTED_BY",
        inverse_uri="sec:claimAssertedBy",
        inverse_label_ja="命題を主張した論文",
        section_comment="論文と主張の関係",
    ),
    Predicate.EVALUATES_TECHNIQUE: PredicateSpec(
        predicate=Predicate.EVALUATES_TECHNIQUE,
        uri="sec:evaluatesTechnique",
        label_ja="評価対象の攻撃手法",
        description_ja="実証評価イベントが検証対象とした攻撃手法との関係",
        domain=EntityType.EVALUATION_RESULT,
        range=EntityType.ATTACK_TECHNIQUE,
        inverse_predicate_name="TECHNIQUE_EVALUATED_IN",
        inverse_uri="sec:techniqueEvaluatedIn",
        inverse_label_ja="攻撃手法が検証された評価イベント",
        section_comment="評価イベントと攻撃手法の関係",
    ),
    Predicate.EVALUATES_CLAIM: PredicateSpec(
        predicate=Predicate.EVALUATES_CLAIM,
        uri="sec:evaluatesClaim",
        label_ja="主張を実証・評価する",
        description_ja="実証評価イベントが論文の主張を客観的に評価する関係",
        domain=EntityType.EVALUATION_RESULT,
        range=EntityType.CLAIM,
        inverse_predicate_name="CLAIM_EVALUATED_IN",
        inverse_uri="sec:claimEvaluatedIn",
        inverse_label_ja="主張の実証評価イベント",
        section_comment="評価イベントと主張の関係",
    ),
    Predicate.YIELDS_EVALUATION: PredicateSpec(
        predicate=Predicate.YIELDS_EVALUATION,
        uri="sec:yieldsEvaluation",
        label_ja="実証評価結果を導出・報告する",
        description_ja="論文が実証実験評価イベントを結果として導出・報告する関係",
        domain=EntityType.PAPER,
        range=EntityType.EVALUATION_RESULT,
        inverse_predicate_name="EVALUATION_YIELDED_BY",
        inverse_uri="sec:evaluationYieldedBy",
        inverse_label_ja="実証評価結果を導出した論文",
        section_comment="論文と実証評価イベントの関係",
    ),
}

EXTRA_OBJECT_PROPERTY_SPECS: List[ObjectPropertySpec] = [
    ObjectPropertySpec(
        uri="sec:attributedToActor",
        inverse_uri="sec:actorAttributedIncident",
        label_ja="インシデントの関与アクター",
        inverse_label_ja="アクターが関与したインシデント",
        domain_uri="sec:Incident",
        range_uri="sec:ThreatActor",
        section_comment="インシデントと脅威アクターの関係",
    ),
    ObjectPropertySpec(
        uri="sec:targetsAsset",
        inverse_uri="sec:assetTargetedInIncident",
        label_ja="インシデントの標的資産",
        inverse_label_ja="インシデントで標的とされた資産",
        domain_uri="sec:Incident",
        range_uri="sec:TargetAsset",
        section_comment="インシデントと標的資産の関係",
    ),
]


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
    is_known_exploited: bool = False
    cisa_date_added: str = ""
    cisa_due_date: str = ""
    known_ransomware_campaign_use: str = ""
    cisa_required_action: str = ""
    cvss_score: Optional[float] = None

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
    def get_predicate_spec(cls, predicate: Predicate) -> Optional[PredicateSpec]:
        """Returns the semantic specification (TBox) for the given predicate."""
        return PREDICATE_SPECS.get(predicate)

    @classmethod
    def get_entity_type_spec(cls, entity_type: EntityType) -> Optional[EntityTypeSpec]:
        """Returns the semantic specification (TBox) for the given entity type."""
        return ENTITY_TYPE_SPECS.get(entity_type)

    @classmethod
    def _is_valid_range(cls, predicate: Predicate, dst_type: EntityType) -> bool:
        """Checks if dst_type matches the range specification of predicate."""
        spec = cls.get_predicate_spec(predicate)
        if spec is None:
            return True
        valid_ranges = spec.allowed_ranges if spec.allowed_ranges else (spec.range,)
        return dst_type in valid_ranges

    @classmethod
    def validate_triple(
        cls,
        src_type: EntityType,
        predicate: Predicate,
        dst_type: Optional[EntityType] = None,
    ) -> bool:
        """Validates whether a predicate is logically permissible from src_type (and optionally to dst_type)."""
        allowed = cls.ALLOWED_RELATIONS.get(src_type, set())
        if predicate not in allowed:
            return False
        if dst_type is not None:
            return cls._is_valid_range(predicate, dst_type)
        return True
