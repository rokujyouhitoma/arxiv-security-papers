---
ID: 165
種別: Feature / Ops
優先度: Medium
ステータス: Open (New)
---

# [FEAT/OPS] 全量 OKF 論文アーカイブへの推論ルール（EIROM）適用と確信度・エビデンス付きグラフ再構築バッチの実装 (ID: 165)

## 1. 概要 / Summary
Issue 163（Edge Inference Rule Ontology Master: EIROM）および Issue 162（Edge 推論機構・確信度・エビデンス属性刻印）の完成に伴い、過去に収集・変換された既存の OKF 論文群（`outputs/okf_papers/`）および永続化グラフデータ（`outputs/cti_graph.json` 等）に対し、最新の推論ルール公理と説明責任属性を全量再アノテーション・バックフィルするバッチパイプラインを実装・実行する。

本バッチにより、以下の効果を達成する：
1. **既存論文の CTI メタデータ最新化**:
   - 過去論文の YAML フロントマターやメタデータに対し、判定ルール ID、推論機構、確信度ティア、エビデンススニペットを付与。
2. **グラフデータベースの全エッジ属性エンリッチメント**:
   - `PropertyGraphEngine` 内の全エッジ（`TARGETS`, `PROPOSES_DEFENSE`, `DISCUSSES`）に完全な `edge_props`（`confidence`, `confidence_tier`, `primary_rule_id`, `applied_rules`, `evidences`, `source_text_hash`）を再生成・刻印。
3. **冪等性・差分実行（Idempotent Incremental Execution）**:
   - `source_text_hash` との比較により、テキストに変更のない論文は重複推論をスキップし、新規または差分のみを高速処理。
4. **監査ログ・整合性レポートの自動出力**:
   - 処理件数、推論された脅威テクニック分布、確信度ティア別（HIGH/MEDIUM/LOW）集計レポートを自動出力。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 6 & 11)
  - `docs/designs/DSN-18-property_graph_database_engine.md`
  - `docs/issues/closed/162-enhance-graph-edge-inference-mechanism-and-confidence-attributes.md`
  - `docs/issues/closed/163-implement-edge-inference-rule-ontology-master.md`
  - `src/pipeline/cti_backfill.py`
  - `src/domain/security/cti/graph_bridge.py`
  - `outputs/okf_papers/`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/pipeline/cti_backfill.py`: EIROM ルールレジストリと最新 `TechniqueInferenceEngine` を用いたバックフィルロジックの改修
- [ ] `src/domain/security/cti/graph_bridge.py`: `batch_sync_papers_to_graph` の確信度・ルール保持連携
- [ ] `tests/pipeline/test_cti_backfill.py`: バックフィル処理および冪等性（スキップ・更新）の単体テスト
- [ ] `outputs/cti_graph.json`: 全量エンリッチメント後のグラフデータファイル

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/165-backfill-okf-papers-eirom-confidence`

1. **バッチエンジンの改修**:
   - `cti_backfill.py` に `EdgeInferenceRuleRegistry` を組み込み、各 OKF ファイルからタイトル・アブストラクトを読み出して最新推論を実行。
2. **グラフ永続化更新**:
   - `sync_cti_inferences_to_graph` を介してグラフへ最新エッジプロパティを格納。
3. **品質検証**:
   - 差分実行時の冪等性（再実行してもグラフやメタデータが二重化・破損しないこと）を検証。
   - `make check_format` および `make static_analysis` 適合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `cti_backfill` バッチが既存 OKF 論文群を走査し、最新の EIROM ルールおよび確信度付きで推論を実行できること
- [ ] グラフデータベース上の全エッジに `confidence_tier`, `primary_rule_id`, `evidences` が正しく格納・永続化されること
- [ ] 差分再実行における冪等性が保たれること
- [ ] 単体テストが 100% PASS すること
- [ ] `make check_format` および `make static_analysis` が 100% PASS すること
