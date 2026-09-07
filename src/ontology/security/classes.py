#!/usr/bin/env python3
"""
Security Domain Ontology Classes.
Pure Python declarative class definitions for cybersecurity knowledge representation.
"""

from __future__ import annotations

from ..core.dsl import ontology_class
from .properties import (
    access_level_property,
    analyzes_property,
    arxiv_id_property,
    blocks_property,
    cisa_date_added_property,
    cisa_due_date_property,
    cisa_required_action_property,
    discloses_property,
    exploits_property,
    generates_rule_property,
    has_poc_property,
    identifies_gap_property,
    is_known_exploited_property,
    known_ransomware_campaign_use_property,
    leaves_unaddressed_property,
    mitigates_property,
    presented_at_property,
    proposes_property,
    repo_url_property,
    reproducibility_tier_property,
    requires_precondition_property,
    rule_syntax_property,
    severity_property,
    targets_property,
    verifies_cve_property,
)


@ontology_class(
    uri="sec:Paper",
    label="セキュリティ論文",
    comment="arXiv または IACR 等で公開された学術セキュリティ論文",
)
class Paper:
    """Scholarly security publication."""

    arxiv_id = arxiv_id_property
    discloses = discloses_property
    analyzes = analyzes_property
    proposes = proposes_property
    has_poc = has_poc_property
    presented_at = presented_at_property
    verifies_cve = verifies_cve_property
    identifies_gap = identifies_gap_property


@ontology_class(
    uri="sec:ThreatActor",
    label="脅威アクター",
    comment="サイバー攻撃を仕掛ける国家主導組織、APTグループ、または脅威主体",
)
class ThreatActor:
    """Adversary group or threat actor."""

    pass


@ontology_class(
    uri="sec:AttackTechnique",
    label="攻撃手法",
    comment="MITRE ATT&CK または学術知見で定義される戦術・技術・手順 (TTP)",
)
class AttackTechnique:
    """Tactics, techniques, and procedures (TTPs)."""

    exploits = exploits_property
    targets = targets_property
    requires_precondition = requires_precondition_property


@ontology_class(
    uri="sec:Vulnerability",
    label="脆弱性",
    comment="CWE または CVE で特定されるソフトウェア/システムの弱点およびセキュリティ欠陥",
)
class Vulnerability:
    """Software weakness or security flaw."""

    severity = severity_property
    is_known_exploited = is_known_exploited_property
    cisa_date_added = cisa_date_added_property
    cisa_due_date = cisa_due_date_property
    known_ransomware_campaign_use = known_ransomware_campaign_use_property
    cisa_required_action = cisa_required_action_property


@ontology_class(
    uri="sec:TargetAsset",
    label="対象資産",
    comment="攻撃の標的となるシステム、プロトコル、ハードウェア、またはAIモデル",
)
class TargetAsset:
    """Target component, model, or hardware."""

    pass


@ontology_class(
    uri="sec:DefenseMechanism",
    label="防御策・緩和策",
    comment="攻撃の防止、検知、または被害軽減のために適用される対策技術",
)
class DefenseMechanism:
    """Countermeasure or mitigation technique."""

    mitigates = mitigates_property
    generates_rule = generates_rule_property
    leaves_unaddressed = leaves_unaddressed_property


@ontology_class(
    uri="sec:BenchmarkMetric",
    label="ベンチマーク評価指標",
    comment="攻撃成功率 (ASR)、防御オーバーヘッド、検知精度などの定量的評価尺度",
)
class BenchmarkMetric:
    """Quantitative evaluation metric."""

    pass


@ontology_class(
    uri="sec:Incident",
    label="観測インシデント",
    comment="実世界で発生したサイバー攻撃事案、被害事例、侵害報告",
)
class Incident:
    """Observed real-world cyber incident."""

    severity = severity_property


@ontology_class(
    uri="sec:DetectionRule",
    label="検知ルール",
    comment="Semgrep, Sigma, YARA などの実行可能な防御検知シグネチャ",
)
class DetectionRule:
    """Actionable detection rule or signature."""

    blocks = blocks_property
    rule_syntax = rule_syntax_property


@ontology_class(
    uri="sec:PoCArtifact",
    label="実証コード / アーティファクト",
    comment="論文で公開された攻撃実証コード、GitHub リポジトリ、Docker 環境",
)
class PoCArtifact:
    """Proof of Concept software repository."""

    repo_url = repo_url_property
    reproducibility_tier = reproducibility_tier_property


@ontology_class(
    uri="sec:Precondition",
    label="攻撃前提条件",
    comment="攻撃成立に必要なアクセス権限（Remote/Local/Physical）や脅威モデル",
)
class Precondition:
    """Threat model assumption or access requirement."""

    access_level = access_level_property


@ontology_class(
    uri="sec:ResearchGap",
    label="未解決課題",
    comment="論文で特定されたスケーラビリティ限界、オープン課題、未カバー領域",
)
class ResearchGap:
    """Unaddressed limitation or open research challenge."""

    pass


@ontology_class(
    uri="sec:ResidualRisk",
    label="残存リスク",
    comment="防御策適用後も残存するセキュリティ盲点、迂回ベクトル",
)
class ResidualRisk:
    """Remaining security exposure after mitigations."""

    severity = severity_property


@ontology_class(
    uri="sec:PublicationVenue",
    label="発表会議 / ジャーナル",
    comment="IEEE S&P, USENIX Security, ACM CCS, NDSS などの学術発表会場",
)
class PublicationVenue:
    """Top-tier academic security publication venue."""

    pass
