#!/usr/bin/env python3
"""
Title Translator & Text Normalizer Module
Handles high-accuracy Japanese title translation and terminology mapping.
"""

import re
from typing import Optional


def clean_text(text: Optional[str]) -> str:
    """Removes extra whitespaces and newlines from raw string."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


TITLE_TRANSLATIONS = [
    (
        "Concept Drift Detection and Adaptive Retraining of Malware Classification Models",
        "マルウェア分類モデルにおけるコンセプトドリフト検出と適応的再学習",
    ),
        (
            "LLM-Assisted Dynamic Threat Analysis for Attacker-Reachable Software Weaknesses in Autonomous Vehicles",
            "自動運転車両における攻撃者到達可能なソフトウェア脆弱性のLLM支援動的脅威分析",
        ),
        (
            (
                "Does Fixing Break Security? An Empirical Study of Security "
                "Degradation in Iterative LLM-Driven Infrastructure-as-Code Repair"
            ),
            "修正はセキュリティを損なうか？LLM駆動Infrastructure-as-Codeの反復修復におけるセキュリティ低下の実証研究",
        ),
        (
            "TeleGapper: On the (un)reliability of Privacy Policies in Telegram Mini apps",
            "TeleGapper: Telegramミニアプリにおけるプライバシーポリシーの（不）信頼性に関する検証",
        ),
        (
            "TopoIntent: Compiling Security Intent into Executable, Compliance-Checked Network Topologies",
            "TopoIntent: セキュリティインテントのコンプライアンス検証済み実行可能ネットワークトポロジへのコンパイル",
        ),
        (
            "Privacy-Preserving RAG by Concealing Sensitive Information from External LLMs",
            "外部LLMからの機密情報隠蔽によるプライバシー保護型RAG",
        ),
        (
            "Tracing Provenance and Detecting Tampering with Complementary LLM Watermarks",
            "相補的LLM電子透かしによる出所追跡と改ざん検出",
        ),
        (
            "Correct Is Not Governed: Provenance Integrity in Agentic Workflows",
            "正当性とガバナンスの分離: エージェント型ワークフローにおける出所完全性の検証",
        ),
        (
            "PIPES: Securing Agent Perception with Provenance and Priors",
            "PIPES: 出所と事前知識によるエージェント認識機能のセキュリティ強化",
        ),
        (
            "RealmEye: Virtual Machine Introspection for Arm CCA Realm VMs",
            "RealmEye: Arm CCA Realm VMのための仮想マシン内省技術",
        ),
        (
            "Beyond Source: An Empirical Study of Python Bytecode Security Risks",
            "ソースコードを超えて: Pythonバイトコードにおけるセキュリティリスクの実証研究",
        ),
        (
            "Dissecting Software Graphs: Structural Insights for Driver-Guided Fuzzing",
            "ソフトウェアグラフの解剖: ドライバーガイド型ファジングのための構造的分析",
        ),
        (
            "Discovering Persistent Behavioural Patterns for Interpretable Blockchain Forensics",
            "解釈可能なブロックチェーンフォレンジックのための持続的行動パターンの発見",
        ),
        (
            "Labels Are Not Endpoints: Treatment Leakage and Construct Validity in MCP Agent Security Evaluation",
            "ラベルは終点ではない: MCPエージェントセキュリティ評価における処置漏洩と構成概念妥当性",
        ),
        (
            (
                "Adversarial Robustness in Smishing Detection: A Comparative "
                "Analysis of Adversarial Fragility in Classical vs. Transformer-Based Detection Systems"
            ),
            "スミッシング検出における敵対的堅牢性: 従来手法対Transformer検出系の敵対的脆弱性比較",
        ),
        (
            "Beyond Visual Evidence: Revealing and Mitigating Relational Privacy Leakage in Document MLLMs",
            "視覚的証拠を超えて: ドキュメントMLLMにおける関係性プライバシー漏洩の解明と軽減",
        ),
        (
            "Technical Report on Resilient and Secure Large-Scale Energy Internet Systems",
            "レジリエントかつ安全な大規模エネルギーインターネットシステムに関する技術レポート",
        ),
        (
            (
                "Understanding Backdoor Vulnerabilities in Vertical Federated Learning: "
                "The Gap Between Research and Practice"
            ),
            "垂直型連合学習におけるバックドア脆弱性の理解: 研究と実務の乖離分析",
        ),
        (
            "Beyond Handcrafted Security: Towards Self-Evolving Defense for LLM Agents",
            "手動セキュリティを超えて: LLMエージェントのための自己進化型防御メカニズムへ向けて",
        ),
        (
            (
                "ATOBench: Tracing How Autonomous Penetration-Testing Agents Verify "
                "Vulnerabilities When Target Evidence Lies"
            ),
            "ATOBench: 標的の証拠が偽りの場合の自律型ペネトレーションテストエージェントによる脆弱性検証追跡",
        ),
        (
            "OmniSphinx: Active Mix Networks (Extended Version)",
            "OmniSphinx: アクティブミックスネットワーク（拡張版）",
        ),
        (
            "Combating Knowledge Corruption in Agent Systems: A Byzantine-Tolerant Secure Collaborative RAG Framework",
            "エージェントシステムにおける知識汚染への対抗: バイザンチン耐性を持つ安全な協調型RAGフレームワーク",
        ),
        (
            "Manipulation-Proof Oblivious Audits against Deceptive Model Providers",
            "欺瞞的なモデルプロバイダに対する改ざん耐性を持つオブリビアス監査技術",
        ),
        (
            "Trident : How to Break Deep Reinforcement Learning Cyber Defenses (Agentic)",
            "Trident: 深層強化学習サイバー防御の攻略手法（エージェント型）",
        ),
        (
            "Adversarial Attacks for Good: A Survey of Proactive Protection across the Visual Content Lifecycle",
            "善意の敵対的攻撃: 視覚コンテンツライフサイクル全体における能動的保護に関するサーベイ",
        ),
        (
            "Post-Hoc Trajectory-Risk Certification for Modular LLM-Based Security Agents",
            "モジュール型LLMセキュリティエージェントのための事後軌跡リスク認定機能",
        ),
        (
            "PriDyG: Privacy-preserving Dynamic Graph Inference with LLM-GNN Collaboration",
            "PriDyG: LLMとGNNの協調によるプライバシー保護型動的グラフ推論",
        ),
        (
            "Behavioral Skill Reconstruction: Reconstructing Hidden Functionality from LLM Agent Skills",
            "行動スキル再構築: LLMエージェントスキルからの隠蔽機能の再構成",
        ),
        (
            "Understanding Fault Tolerance of Adversarially Robust Pruned Models",
            "敵対的に堅牢な剪定済みモデルのフォールトトランス耐性の解明",
        ),
        (
            "Open-World Darknet Traffic Recognition Under Leave-One-Service-Out Evaluation",
            "サービス除外評価下におけるオープンワールドダークネットトラフィック識別",
        ),
        (
            "Securing Load Balancing over QUIC",
            "QUICプロトコルにおけるロードバランシングのセキュリティ強化",
        ),
        (
            "Behavioral Information Leakage in Darknet Traffic: A Multi-Channel Analysis Across Anonymity Networks",
            "ダークネットトラフィックにおける行動情報漏洩: 匿名ネットワークを横断するマルチチャネル分析",
        ),
        (
            "NEBULA: A Language - Independent Specification for Opaque Rotating Refresh Tokens",
            "NEBULA: 透過的ローテーションリフレッシュトークンのための言語不可知型仕様",
        ),
        (
            (
                "FBID: Adaptive Personalized Federated Learning for Robust "
                "Out-of-Distribution Attack Detection in IoT Networks"
            ),
            "FBID: IoTネットワークにおける堅牢な分布外攻撃検出のための適応的パーソナライズ連合学習",
        ),
        (
            "An Inline Control Architecture for Language Models in Intelligent Transportation Systems",
            "高度道路交通システムにおける言語モデルのためのインライン制御アーキテクチャ",
        ),
        (
            (
                "Delay Attacks on the German Smart Metering Infrastructure: "
                "A Security Analysis of CLS Channel Timing Constraints"
            ),
            "ドイツのスマートメーターインフラに対する遅延攻撃: CLSチャネルタイミング制約のセキュリティ分析",
        ),
        (
            (
                "When Agents Learn to Be You: Benchmarking Privacy Leakage, "
                "Impersonation Risk, and Defenses in Persona Skills"
            ),
            "エージェントがあなたを学習するとき: ペルソナスキルにおけるプライバシー漏洩、なりすましリスク、および防御のベンチマーク",
        ),
        (
            "Empirical Analysis of Evasion and Poisoning Against Malware Data Drift Detection",
            "マルウェアデータドリフト検出に対する回避およびポイズニング攻撃の実証分析",
        ),
        (
            "A Security-Oriented Lifecycle Model for Large Language Model Systems",
            "大規模言語モデルシステムのためのセキュリティ指向ライフサイクルモデル",
        ),
        (
            (
                "DiagChain: A Diagnostic Benchmark for Evaluating LLM Agents "
                "on Evidence-Grounded Attack Chain Reconstruction"
            ),
            "DiagChain: 証拠に基づく攻撃チェーン再構築におけるLLMエージェント評価用診断ベンチマーク",
        ),
        (
            "SkillJack: Persistent Skill Backdoors in Self-Evolving Agents",
            "SkillJack: 自己進化型エージェントにおける持続的スキルバックドア攻撃",
        ),
        (
            "SkillSentry: Adaptive Honey Worlds for Dynamic Safety Testing of Agent Skills",
            "SkillSentry: エージェントスキルの動的安全テストのための適応型ハニーワールド",
        ),
        (
            "MutMem: Cryptographically Authorized Mutation in Persistent Agent Memory",
            "MutMem: 持続的エージェントメモリにおける暗号認証付きデータ変容プロトコル",
        ),
    ]

TITLE_REPLACEMENTS = [
    (r"An Empirical Study of (.*)", r"\1の実証研究"),
    (r"Towards (.*)", r"\1に向けて"),
    (r"Detection of (.*)", r"\1の検出"),
    (r"Mitigating (.*) via (.*)", r"\2による\1の軽減"),
    (r"Securing (.*)", r"\1のセキュリティ強化"),
    (r"Analysis of (.*)", r"\1の分析"),
    (r"Benchmarking (.*)", r"\1のベンチマーク評価"),
    (r"Adversarial Attacks on (.*)", r"\1に対する敵対的攻撃"),
    (r"Vulnerability Detection", "脆弱性検出"),
    (r"Malware Detection", "マルウェア検出"),
    (r"Privacy Policy", "プライバシーポリシー"),
    (r"Autonomous Vehicles", "自動運転車両"),
    (r"Infrastructure-as-Code", "Infrastructure-as-Code"),
    (r"Large Language Models", "大規模言語モデル"),
    (r"LLM Agents", "LLMエージェント"),
    (r"Cybersecurity", "サイバーセキュリティ"),
    (r"Federated Learning", "連合学習"),
]


def _lookup_exact_translation(title_lower: str) -> Optional[str]:
    """Finds exact or substring matched translation from translation table."""
    for en, ja in TITLE_TRANSLATIONS:
        if en.lower() in title_lower or title_lower in en.lower():
            return ja
    return None


def _apply_pattern_translation(title: str) -> str:
    """Applies regex pattern replacements for common academic security title structures."""
    for pattern, repl in TITLE_REPLACEMENTS:
        if re.search(pattern, title, re.IGNORECASE):
            return re.sub(pattern, repl, title, flags=re.IGNORECASE)
    return f"{title}（セキュリティ分析論文）"


def translate_title_ja(title: str) -> str:
    """Translates paper title to fluent Japanese security terminology."""
    t = clean_text(title)
    if not t:
        return ""

    exact_ja = _lookup_exact_translation(t.lower())
    if exact_ja:
        return exact_ja

    return _apply_pattern_translation(t)
