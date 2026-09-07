#!/usr/bin/env python3
"""
Security Domain Ontology Properties (Relations and Datatype Attributes).
Declarative definitions of object and datatype properties in the CTI domain.
"""

from __future__ import annotations

from ..core.dsl import DatatypePropertyField, ObjectPropertyField

# Object Properties (Relations between entities)
exploits_property = ObjectPropertyField(
    uri="sec:exploits",
    label="悪用する",
    comment="攻撃手法が特定の脆弱性または弱点を悪用することを示す関係",
    range="sec:Vulnerability",
    inverse_of="sec:exploitedBy",
)

targets_property = ObjectPropertyField(
    uri="sec:targets",
    label="標的とする",
    comment="攻撃手法が標的とするシステム、資産、AIモデル、またはプロトコル",
    range="sec:TargetAsset",
    inverse_of="sec:targetedBy",
)

mitigates_property = ObjectPropertyField(
    uri="sec:mitigates",
    label="緩和・防御する",
    comment="防御策が特定の攻撃手法を無力化・低減することを示す関係",
    range="sec:AttackTechnique",
    inverse_of="sec:mitigatedBy",
)

blocks_property = ObjectPropertyField(
    uri="sec:blocks",
    label="阻止・検知する",
    comment="検知ルールが特定の攻撃手法の実行を遮断・検知することを示す関係",
    range="sec:AttackTechnique",
    inverse_of="sec:blockedBy",
)

generates_rule_property = ObjectPropertyField(
    uri="sec:generatesRule",
    label="検知ルールを生成する",
    comment="防御手法から具体的な検知ルール（Semgrep/Sigma/YARA）が導出される関係",
    range="sec:DetectionRule",
    inverse_of="sec:generatedFrom",
)

requires_precondition_property = ObjectPropertyField(
    uri="sec:requiresPrecondition",
    label="前提条件を要求する",
    comment="攻撃または検証の成立に特定のアクセス権限や脅威モデル知識を要求する関係",
    range="sec:Precondition",
    inverse_of="sec:preconditionFor",
)

identifies_gap_property = ObjectPropertyField(
    uri="sec:identifiesGap",
    label="課題・ギャップを特定する",
    comment="論文が未解決のセキュリティ課題やスケーラビリティ制約を特定する関係",
    range="sec:ResearchGap",
    inverse_of="sec:identifiedIn",
)

leaves_unaddressed_property = ObjectPropertyField(
    uri="sec:leavesUnaddressed",
    label="残存リスクを残す",
    comment="提案された防御策の適用後も残存するセキュリティ盲点や未対応リスク",
    range="sec:ResidualRisk",
    inverse_of="sec:unaddressedIn",
)

has_poc_property = ObjectPropertyField(
    uri="sec:hasPoC",
    label="実証コードを有する",
    comment="論文が公開された攻撃・検証実証コード（PoC）リポジトリを有する関係",
    range="sec:PoCArtifact",
    inverse_of="sec:pocOf",
)

presented_at_property = ObjectPropertyField(
    uri="sec:presentedAt",
    label="発表された",
    comment="論文が査読採択・発表された国際会議または学術アーカイブ会場",
    range="sec:PublicationVenue",
    inverse_of="sec:hostedPaper",
)

verifies_cve_property = ObjectPropertyField(
    uri="sec:verifiesCVE",
    label="脆弱性を検証する",
    comment="論文が具体的な CVE 脆弱性の悪用・修正を実証検証する関係",
    range="sec:Vulnerability",
    inverse_of="sec:verifiedIn",
)

discloses_property = ObjectPropertyField(
    uri="sec:discloses",
    label="開示・報告する",
    comment="論文が未知または既知の脆弱性・弱点を開示・分析することを示す関係",
    range="sec:Vulnerability",
    inverse_of="sec:disclosedIn",
)

analyzes_property = ObjectPropertyField(
    uri="sec:analyzes",
    label="分析する",
    comment="論文が特定の攻撃手法、脆弱性、または資産の挙動を詳細解析する関係",
    range="sec:AttackTechnique",
    inverse_of="sec:analyzedIn",
)

proposes_property = ObjectPropertyField(
    uri="sec:proposes",
    label="提案する",
    comment="論文が新しい防御メカニズムやアルゴリズムを提案することを示す関係",
    range="sec:DefenseMechanism",
    inverse_of="sec:proposedIn",
)

# Datatype Properties (Literal Attributes)
arxiv_id_property = DatatypePropertyField(
    uri="sec:arxivId",
    label="arXiv ID",
    comment="arXiv における一意の論文識別子 (例: 2403.12345)",
    range="xsd:string",
    is_functional=True,
)

severity_property = DatatypePropertyField(
    uri="sec:severity",
    label="重要度・深刻度",
    comment="脆弱性またはリスクの深刻度評価 (Critical, High, Medium, Low)",
    range="xsd:string",
)

access_level_property = DatatypePropertyField(
    uri="sec:accessLevel",
    label="アクセス要求水準",
    comment="攻撃成立に必要なアクセス権限 (Remote, Local, Physical, Root)",
    range="xsd:string",
)

repo_url_property = DatatypePropertyField(
    uri="sec:repoUrl",
    label="リポジトリURL",
    comment="公開ソースコードまたはPoCアーティファクトのURL",
    range="xsd:anyURI",
)

rule_syntax_property = DatatypePropertyField(
    uri="sec:ruleSyntax",
    label="ルール構文・シグネチャ",
    comment="実行可能な検知ルール定義テキスト",
    range="xsd:string",
)

reproducibility_tier_property = DatatypePropertyField(
    uri="sec:reproducibilityTier",
    label="再現性評価ティア",
    comment="学術アーティファクトの再現性評価バッジ (Artifact Evaluated, Available)",
    range="xsd:string",
)

is_known_exploited_property = DatatypePropertyField(
    uri="sec:isKnownExploited",
    label="CISA KEV悪用確認フラグ",
    comment="CISA KEV (Known Exploited Vulnerabilities) カタログ掲載有無フラグ",
    range="xsd:boolean",
)

cisa_date_added_property = DatatypePropertyField(
    uri="sec:cisaDateAdded",
    label="CISA KEV追加日",
    comment="CISA KEV カタログに登録された日付 (YYYY-MM-DD)",
    range="xsd:date",
)

cisa_due_date_property = DatatypePropertyField(
    uri="sec:cisaDueDate",
    label="CISA是正対応期限",
    comment="CISA BOD 22-01 に基づく是正措置対応期限 (YYYY-MM-DD)",
    range="xsd:date",
)

known_ransomware_campaign_use_property = DatatypePropertyField(
    uri="sec:knownRansomwareCampaignUse",
    label="ランサムウェア悪用確認フラグ",
    comment="ランサムウェアキャンペーンでの悪用事実 (Known / Unknown)",
    range="xsd:string",
)

cisa_required_action_property = DatatypePropertyField(
    uri="sec:cisaRequiredAction",
    label="CISA要求対策アクション",
    comment="CISA が連邦機関および管理者に要求するパッチ・緩和アクション",
    range="xsd:string",
)
