---
ID: 163
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Vertex紐付け推論判定ルール（Edge Inference Rule Ontology Master: EIROM）のマスターデータ化およびオントロジー推論基盤の実装 (ID: 163)

## 1. 概要 / Summary
グラフデータベース（`src/graph/` PropertyGraphEngine）において、Paper 頂点と Threat / Technique / Vulnerability / Mitigation 頂点、あるいは Technique と Mitigation / CWE 頂点間を紐付ける際の**判断ルール（判定基準・条件・重み・エビデンス抽出仕様）をコード上のハードコードから完全に分離し、独立した「推論ルール・オントロジーマスターデータ（Edge Inference Rule Ontology Master: EIROM）」として一元管理**する。

これはセキュリティ知識オントロジー（SKO: `DSN-17` Rev 2.0 Section 11）における推論公理（TBox Inference Rules）の中核を成すものであり、ルールの外部定義化（マスターデータ化）、バージョニング、動的ロード、およびルール変更時のグラフ差分再評価（Invalidation Lifecycle）を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 11: EIROM 仕様)
  - `docs/designs/DSN-18-property_graph_database_engine.md`
  - `docs/issues/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md`
  - `src/ontology/schema.py` (SecurityOntologySchema, EntityType, Predicate)
  - `src/graph/structures.py` (Vertex, Edge)
  - `src/domain/security/cti/inference.py` (TechniqueInferenceEngine)
  - `src/domain/security/cti/graph_bridge.py` (sync_cti_inferences_to_graph)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **マスターデータの改ざん防止・完全性検証**:
   - `master_rules.json` のロード時にスキーマバリデーションおよび暗号学的 SHA-256 フィンガープリントを算出し、未承認のルール書き換えや破損データを即時検知・拒絶する。
2. **安全な正規表現と DoS 防止（ReDoS 防護）**:
   - ルールマスターに登録される正規表現パターン（例: `r"\b(T\d{4}(?:\.\d{3})?)\b"`）は、指数関数バックトラック（ReDoS）を引き起こさない安全なパターンに限定し、バリデータで事前検証する。
3. **推論実行時の型安全性とフォールバック**:
   - ルールマスターファイルが一時的に読み込めない場合でも、システムがクラッシュせず内製デフォルト公理（Fallback Builtin Rules）で安全に稼働継続できるフェイルセーフ設計とする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/ontology/rule_schema.py`: 推論ルールマスターのデータ構造・型定義・バリデータ（`EdgeInferenceRule`, `RuleConditionType`, `ConfidenceTier`, `EvidenceExtractionSpec`）
- [x] `src/ontology/rules/master_rules.json`: 標準オントロジー推論ルールマスターデータ定義ファイル（12大標準ルール）
- [x] `src/ontology/rule_registry.py`: ルールマスターのローダー、スキーマ検証器、クエリ・適用エンジン（`EdgeInferenceRuleRegistry`）
- [x] `src/domain/security/cti/inference.py`: ハードコード辞書から `EdgeInferenceRuleRegistry` 駆動型推論へのリファクタリング
- [x] `src/ontology/__init__.py`: 新規モジュールのエクスポート追加
- [x] `tests/ontology/test_rule_ontology_master.py`: ルールマスター検証・ロード・推論適用の包括的単体テスト

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/163-edge-inference-rule-ontology-master`

### 5.1 推論ルールマスターのメタスキーマ設計 (`src/ontology/rule_schema.py`)
- **列挙型定義**:
  - `RuleConditionType`: `"regex"`, `"lexical"`, `"semantic_threshold"`, `"catalog_axiom"`, `"context_ratio"`
  - `ConfidenceTier`: `"HIGH"`, `"MEDIUM"`, `"LOW"`
- **`EvidenceExtractionSpec` データクラス**:
  - `target_field: str`: 抽出対象セクション（`"title"`, `"abstract"`, `"fulltext"`）
  - `max_snippet_length: int = 120`: 証拠スニペット長上限
  - `case_sensitive: bool = False`
- **`EdgeInferenceRule` データクラス (`frozen=True`)**:
  - `rule_id: str`: 一意識別子（例: `"RULE-EDGE-PAPER-TECH-REGEX-01"`）
  - `name: str`: ルール表示名
  - `description: str`: 推論論理の説明
  - `source_label: str`: 始点頂点ラベル（`"Paper"`, `"DefenseMitigation"`, etc.）
  - `target_label: str`: 終点頂点ラベル（`"AttackTechnique"`, `"CWE"`, etc.）
  - `edge_label: str`: 付与されるエッジ述語（`"TARGETS"`, `"PROPOSES_DEFENSE"`, `"DISCUSSES"`, `"MITIGATES"`, `"EXPLOITS_VULNERABILITY"`）
  - `condition_type: RuleConditionType`: 判定条件型
  - `condition_spec: Dict[str, Any]`: 条件パラメータ（正規表現文字列、語彙リスト、閾値）
  - `base_confidence: float`: 基本確信度（0.0 〜 1.0）
  - `confidence_tier: ConfidenceTier`: 確信度階層
  - `evidence_spec: EvidenceExtractionSpec`: エビデンス生成仕様
  - `version: str`: ルールバージョン（例: `"2026.09.1"`）
  - `is_active: bool = True`: 有効/無効フラグ
  - `validate() -> None`: スキーマ妥当性・正規表現コンパイルテスト

### 5.2 標準オントロジー推論ルールマスターデータ (`src/ontology/rules/master_rules.json`)
`DSN-17` Rev 2.0 Section 11 に準拠した標準 12 ルールを JSON 形式で定義：
1. `RULE-EDGE-PAPER-TECH-REGEX-01`: Direct Technique ID Match (確信度 1.0, HIGH)
2. `RULE-EDGE-PAPER-TECH-TITLE-02`: Title Technique Name Affinity (確信度 0.8, HIGH)
3. `RULE-EDGE-PAPER-TECH-KEYWORD-03`: Title Important Keyphrase Match (確信度 0.5, MEDIUM)
4. `RULE-EDGE-PAPER-TECH-ABSTRACT-04`: Abstract Lexical Scoring (確信度 0.4〜0.7, MEDIUM)
5. `RULE-EDGE-PAPER-CWE-REGEX-01`: Direct CWE Weakness Identification (確信度 1.0, HIGH)
6. `RULE-EDGE-PAPER-TECH-STACK-01`: Target Technology Stack Identification (確信度 0.7, MEDIUM)
7. `RULE-EDGE-PAPER-DEFENSE-01`: Proposed Defense Method Identification (確信度 0.8, HIGH)
8. `RULE-EDGE-TECH-MITIGATE-AXIOM-01`: ATT&CK Mitigation Axiom (確信度 1.0, HIGH)
9. `RULE-EDGE-TECH-CWE-AXIOM-02`: CAPEC/CWE Exploitation Axiom (確信度 0.9, HIGH)
10. `RULE-EDGE-MITIGATION-CONTROL-01`: Mitigation to NIST/CIS Control Mapping (確信度 0.85, HIGH)
11. `RULE-EDGE-FOCUS-OFFENSIVE-01`: Offensive Context Modifier (Edge: `TARGETS`)
12. `RULE-EDGE-FOCUS-DEFENSIVE-02`: Defensive Context Modifier (Edge: `PROPOSES_DEFENSE`)

### 5.3 ルールレジストリ (`src/ontology/rule_registry.py`)
- **`EdgeInferenceRuleRegistry` クラス**:
  - `load_from_json(path: Optional[str] = None) -> None`: JSON ファイルからルールマスターをロード
  - `load_builtin_rules() -> None`: 外部ファイル不在時のフォールバック組み込み公理
  - `get_rule(rule_id: str) -> Optional[EdgeInferenceRule]`: ルールID単体取得
  - `get_rules_for_pair(source_label: str, target_label: str) -> List[EdgeInferenceRule]`: 始点・終点ペアに応じた高速インデックス引き
  - `get_active_rules() -> List[EdgeInferenceRule]`: 有効ルール全量取得
  - `compute_ruleset_hash() -> str`: ルールセット全体の SHA-256 フィンガープリント算出

### 5.4 推論エンジンのリファクタリング (`src/domain/security/cti/inference.py`)
- `TechniqueInferenceEngine` の初期化時に `rule_registry: Optional[EdgeInferenceRuleRegistry] = None` を注入可能にする。
- ハードコードされていた判定ロジックを、レジストリから取得したルール群の評価ループへと昇華。
- 推論結果（`InferredTechnique`）に適用された `applied_rules` および `primary_rule_id` を自動設定。

### 5.5 制約・品質保証
- **外部依存ゼロ**: Python 標準ライブラリ (`json`, `re`, `hashlib`, `pathlib`, `typing`, `enum`, `dataclasses`) のみ使用。
- **Xenon 循環的複雑度**: 全関数・メソッド $\le 5$ (Rank A 必須)。
- **Mypy `--strict` 適合**: 100% 型安全。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `src/ontology/rule_schema.py` に `EdgeInferenceRule` および関連型が完全実装されていること
- [x] `src/ontology/rules/master_rules.json` に標準 12 推論ルールが定義され、構文・型妥当性が 100% PASS すること
- [x] `EdgeInferenceRuleRegistry` がルールマスターをロードし、始点/終点ペア別の高速逆引きが正常動作すること
- [x] `TechniqueInferenceEngine` がルールマスター駆動型にリファクタリングされ、適用ルールIDが出力されること
- [x] 単体テスト `tests/ontology/test_rule_ontology_master.py` が新規作成され 100% PASS すること
- [x] 既存の全単体テスト（`tests/domain/test_stix_navigator.py` 等）が互換性を保ち 100% PASS すること
- [x] `make check_format` および `make static_analysis` (radon, xenon Rank A, flake8, mypy --strict) が 100% PASS すること
