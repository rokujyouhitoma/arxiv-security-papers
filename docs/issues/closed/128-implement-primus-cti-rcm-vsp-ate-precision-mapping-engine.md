---
ID: 128
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PRIMUS知見に基づくCWE/CVSS/ATT&CK精密マッピングエンジン（CTI-RCM, CTI-VSP, CTI-ATE）と来歴階層化の実装 (ID: 128)

## 1. 概要 / Summary
自然言語で記述された論文のアブストラクトや本文から標準セキュリティ識別子を高精度に特定するため、サイバーセキュリティ専門評価体系（PRIMUS / CTI-Bench）の知見を取り入れた精密マッピングエンジンを Pure Python（ゼロ外部依存）で実装する。

具体的には、根本原因から CWE 分類を導出する CTI-RCM（Root Cause Mapping）、攻撃前提条件や影響範囲から CVSS v3.1/v4.0 深刻度ベクトルを推定する CTI-VSP（Vulnerability Severity Prediction）、攻撃手順・戦術から MITRE ATT&CK テクニック ID を特定する CTI-ATE（Attack Technique Extraction）の 3 系統推論モジュールを構築する。さらに、明示的言及に基づく確証（Gold Tier）と推論ヒューリスティクス（Silver Tier）を分離管理する「来歴階層化（Provenance Tiering）」を導入し、CTI ナレッジグラフの信頼性を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- [DSN-17: セキュリティ知識オントロジー](../../docs/designs/DSN-17-security_knowledge_ontology.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-RES-02, UC-DEV-02)](../requirements/REQ-03-use_case_ledger.md)
- [[MNG-02] MITRE ATT&CK & CWE 統合ナレッジグラフ対応台帳](../processes/MNG-02-mitre_attack_cwe_ledger.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 127: OASIS STIX 2.1仕様準拠 SDO/SRO 脅威インテリジェンス](127-implement-stix-21-sdo-sro-threat-knowledge-graph-generation.md)
- [src/ontology/taxonomy.py](../../src/ontology/taxonomy.py)
- [src/ontology/extractor.py](../../src/ontology/extractor.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-128-01: 偽陽性マッピングによる深刻度誤判定およびアラート疲弊 (Classification Poisoning)**
  - *脅威*: 論文内の単なる言及や過去の脆弱性引用を新規ゼロデイの発見と誤判定し、CVSS 10.0 や緊急アラートを誤発報させる。
  - *対策*: 文脈判定（新規発見 vs 既知引用の構文スコア）を導入し、確証度スコア（Confidence Score）が閾値（Gold $\ge 0.85$, Silver $\ge 0.60$）に満たない低信頼度ノードは自動破棄（Bronze / Reject）。
- **T-128-02: 攻撃者による学術要約への敵対的語彙挿入 (Adversarial Text Evasion)**
  - *脅威*: 論文提出者が意図的に特定キーワード（例: "sandbox bypass"）を散りばめ、誤った ATT&CK ID（例: T1059）に誘導する。
  - *対策*: 単語の一致だけでなく、CWE 階層関係（`TaxonomyRegistry` の親祖先関係）および動詞・目的語ペア（`action` + `target`）の共起検証を必須化。
- **T-128-03: 複雑正規表現による正規表現破綻 (ReDoS)**
  - *脅威*: テキスト中の CVE / CWE / ATT&CK パターン検出用正規表現にバックトラックを誘発するパターンが含まれ、解析がハングアップする。
  - *対策*: 非バックトラックの決定論的正規表現パターン（事前コンパイル済み）のみを使用し、テキスト長の上限チェック（最大 50,000 文字）を実施。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/ontology/primus/__init__.py` (PRIMUS パッケージエクスポート)
- [x] `src/ontology/primus/rcm.py` (CTI-RCM: 脆弱性根本原因 $\rightarrow$ CWE 推論モジュール)
- [x] `src/ontology/primus/vsp.py` (CTI-VSP: 影響範囲 $\rightarrow$ CVSS v3.1/v4.0 推定モジュール)
- [x] `src/ontology/primus/ate.py` (CTI-ATE: 攻撃手順 $\rightarrow$ MITRE ATT&CK テクニック抽出モジュール)
- [x] `src/ontology/primus/provenance.py` (確証度判定および Gold/Silver 来歴管理)
- [x] `src/ontology/extractor.py` (PRIMUS エンジンの統合)
- [x] `tests/ontology/test_primus_mapping.py` (CTI-RCM, CTI-VSP, CTI-ATE 単体・複合テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/128-implement-primus-cti-rcm-vsp-ate-precision-mapping-engine`

1. **ステップ 1: CTI-RCM (Root Cause Mapping) の実装 (`src/ontology/primus/rcm.py`)**:
   - 論文の脆弱性記述（例: "buffer overflow", "out-of-bounds write", "race condition", "SQL injection"）から対応する CWE ID（CWE-119, CWE-787, CWE-362, CWE-89 等）をマッピングするパターンマッチングエンジンを実装。
   - CWE 階層（View 1000, Top 25 2023/2024）に基づく正規化と、最も具体的な子 CWE（Specific Leaf Node）への絞り込み。
2. **ステップ 2: CTI-VSP (Vulnerability Severity Prediction) の実装 (`src/ontology/primus/vsp.py`)**:
   - 論文から攻撃経路（Attack Vector: Network / Adjacent / Local / Physical）、攻撃難易度（Attack Complexity: Low / High）、必要権限（Privileges Required）、ユーザ関与（User Interaction）、影響範囲（Scope）、機密性・完全性・可用性影響（CIA Impact）の各メトリクスを推定。
   - 標準 CVSS v3.1 ベクトル文字列（例: `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H`）および基本スコア（Base Score）の数式計算を Pure Python で完遂。
3. **ステップ 3: CTI-ATE (Attack Technique Extraction) の実装 (`src/ontology/primus/ate.py`)**:
   - MITRE ATT&CK Enterprise（例: T1059, T1190, T1068）および MITRE ATLAS（例: AML.T0000, AML.T0015）の戦術（Tactics）と手法（Techniques）を抽出。
   - 論文内の PoC 手法やシステムコールの記述から ATT&CK ID へのマッピングを特定。
4. **ステップ 4: 来歴階層化エンジンの実装 (`src/ontology/primus/provenance.py`)**:
   - `ProvenanceRecord` クラスを定義（`tier`: "gold" | "silver", `confidence`: float, `evidence`: str, `source_rule`: str）。
   - 論文中に明示的に「CWE-xxx」「Txxxx」の文字列が存在する場合は Gold Tier（Confidence 0.95）。自然言語パターンの推論マッチングの場合は Silver Tier（Confidence 0.65〜0.85）。
5. **ステップ 5: テストスイートと品質検証**:
   - `tests/ontology/test_primus_mapping.py` で代表的セキュリティ論文（メモリ破壊、サイドチャネル、LLMインジェクション等）のテキストに対するマッピング正当性を検証。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 論文要約から CWE ID、CVSS v3.1 ベクトル文字列、MITRE ATT&CK ID が外部依存なしに自動抽出されること
- [x] CVSS v3.1 基本スコア計算アルゴリズムが FIRST.org 公式仕様と 100% 一致すること
- [x] 明示的ラベル（Gold Tier）と推論ラベル（Silver Tier）がメタデータ上で明確に分離・識別できること
- [x] 確証度 0.60 未満の低品質な推定結果が安全に破棄されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
