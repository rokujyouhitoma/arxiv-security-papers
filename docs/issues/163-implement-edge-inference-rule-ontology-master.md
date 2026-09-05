---
ID: 163
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Vertex紐付け推論判定ルール（Edge Inference Rule Ontology Master）のマスターデータ化およびオントロジー推論基盤の実装 (ID: 163)

## 1. 概要 / Summary
グラフデータベース（`src/graph/` PropertyGraphEngine）において、Paper 頂点と Threat / Technique / Vulnerability / Mitigation 頂点、あるいは Technique と Mitigation / CWE 頂点間を紐付ける際の**判断ルール（判定基準・条件・重み・エビデンス抽出仕様）をコード上のハードコードから完全に分離し、独立した「推論ルール・オントロジーマスターデータ（Edge Inference Rule Ontology Master: EIROM）」として一元管理**する。

これはセキュリティ知識オントロジー（SKO: `DSN-17`）における推論公理（TBox Inference Rules）の中核を成すものであり、ルールの外部定義化（マスターデータ化）、バージョニング、動的ロード、およびルール変更時のグラフ差分再評価を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Section 8 新設)
  - `docs/designs/DSN-18-property_graph_database_engine.md`
  - `docs/issues/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md`
  - `src/ontology/schema.py` (SecurityOntologySchema)
  - `src/graph/structures.py` (Vertex, Edge)
  - `src/domain/security/cti/inference.py` (TechniqueInferenceEngine)
  - `src/domain/security/cti/graph_bridge.py` (Graph Bridge)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [docs/designs/DSN-17-security_knowledge_ontology.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-17-security_knowledge_ontology.md): Section 8「Vertex間エッジ紐付け判定ルールマスター仕様」の追加
- [ ] [src/ontology/rule_schema.py](file:///workspace/arxiv-security-papers/src/ontology/rule_schema.py): 推論ルールマスターのデータ構造・バリデータ（EdgeInferenceRule, RuleCondition, EvidenceRuleSpec）
- [ ] [src/ontology/rules/master_rules.json](file:///workspace/arxiv-security-papers/src/ontology/rules/master_rules.json): 標準オントロジー推論ルールマスターデータ定義ファイル
- [ ] [src/ontology/rule_registry.py](file:///workspace/arxiv-security-papers/src/ontology/rule_registry.py): ルールマスターのローダー、スキーマ検証器、クエリ・適用エンジン
- [ ] [src/domain/security/cti/inference.py](file:///workspace/arxiv-security-papers/src/domain/security/cti/inference.py): ルールマスター駆動型推論への移行（ハードコード排除）
- [ ] [src/domain/security/cti/graph_bridge.py](file:///workspace/arxiv-security-papers/src/domain/security/cti/graph_bridge.py): ルールマスター参照による Edge 属性・エビデンス自動生成
- [ ] [tests/ontology/test_rule_ontology_master.py](file:///workspace/arxiv-security-papers/tests/ontology/test_rule_ontology_master.py): ルールマスター整合性・推論適用の単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/163-edge-inference-rule-ontology-master`

1. **推論ルールマスターのスキーマ設計 (`src/ontology/rule_schema.py`)**:
   - `EdgeInferenceRule`:
     - `rule_id`: 一意識別子（例: `RULE-EDGE-PAPER-ATTACK-001`）
     - `name`: ルール表示名
     - `description`: ルールの推論論理説明
     - `source_label`: 始点頂点ラベル（`Paper`, `AttackTechnique`, etc.）
     - `target_label`: 終点頂点ラベル（`AttackTechnique`, `DefenseMitigation`, `Vulnerability`, etc.）
     - `edge_label`: 付与されるエッジ述語（`TARGETS`, `PROPOSES_DEFENSE`, `DISCUSSES`, `MITIGATES`, `EXPLOITS_VULNERABILITY`）
     - `condition_type`: 判定条件型（`regex`, `lexical`, `semantic_threshold`, `catalog_relation`）
     - `condition_params`: パラメータ（正規表現パターン、語彙セット、スコア計算式）
     - `base_confidence`: 基本確信度（0.0 〜 1.0）
     - `confidence_tier`: `HIGH` / `MEDIUM` / `LOW`
     - `evidence_template`: エビデンス生成テンプレート（スニペット抽出規則）
     - `version`: ルール改訂バージョン（例: `"2026.09.1"`）
     - `is_active`: 有効フラグ
2. **標準マスターデータ定義ファイル (`src/ontology/rules/master_rules.json`)**:
   - Paper ↔ AttackTechnique 直接検知ルール (`RULE-EDGE-PAPER-ATTACK-REGEX-01`)
   - Paper ↔ AttackTechnique タイトル語彙一致ルール (`RULE-EDGE-PAPER-ATTACK-TITLE-02`)
   - Paper ↔ AttackTechnique 要約専門語彙スコアリングルール (`RULE-EDGE-PAPER-ATTACK-ABSTRACT-03`)
   - AttackTechnique ↔ DefenseMitigation 緩和関係公理ルール (`RULE-EDGE-TECH-MITIGATE-AXIOM-01`)
   - AttackTechnique ↔ Vulnerability/CWE 悪用脆弱性マッピングルール (`RULE-EDGE-TECH-CWE-AXIOM-02`)
   - Paper 攻防コンテキスト分類ルール (`RULE-EDGE-FOCUS-OFFENSIVE-01`, `RULE-EDGE-FOCUS-DEFENSIVE-02`)
3. **ルールレジストリ (`src/ontology/rule_registry.py`)**:
   - ルールマスターのオンデマンド読み込み、JSONスキーマ整合性検証、ルールのインデックス化（source/targetペア別）
4. **推論エンジン・グラフブリッジへの注入**:
   - `TechniqueInferenceEngine` が `RuleRegistry` を利用して動的にルールを適用し、ルールID・エビデンスを自動生成

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `DSN-17` に Section 8（Vertex間エッジ紐付け判定ルールマスター仕様）が正式反映されていること
- [ ] `EdgeInferenceRule` スキーマおよびバリデータが型安全に実装されていること
- [ ] `src/ontology/rules/master_rules.json` に標準推論ルール群が定義され、ロード・検証できること
- [ ] `RuleRegistry` が始点/終点頂点ラベルに応じた適用可能ルール群を高速に取得できること
- [ ] ハードコードされていた推論ルールがマスターデータ駆動型にリファクタリングされること
- [ ] 単体テスト `tests/ontology/test_rule_ontology_master.py` が 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (xenon Rank A, mypy --strict) が 100% PASS すること
