---
ID: 188
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 実論文データ ABox への新実体統合と因果・エビデンス探索の実装 (ID: 188)

## 1. 概要 / Summary
Phase 1〜3（[Issue 184](184-enhance-owl-logic-incident-coupling-and-standards-alignment.md), [Issue 185](185-implement-threat-model-causality-impact-and-precondition-neutralization.md), [Issue 186](186-implement-claim-evidence-reification-and-regex-data-constraints.md)）で策定した W3C OWL / Google OKF 準拠のセキュリティオントロジー `security_ontology_v2.ttl` (TBox) に基づき、実論文データ（ABox）の抽出・グラフインジェストパイプラインを拡張する。
論文の OKF メタデータおよび本文テキストから、被害影響（`Impact`）、攻撃前提条件の無力化（`neutralizesPrecondition`）、学術的主張（`Claim`）、実証評価結果（`EvaluationResult`）、および実世界インシデント（`Incident`）を自動抽出し、PropertyGraphEngine に ABox ノードおよび因果エッジとして格納する。
これにより、GraphRAG における「論文主張 $\rightarrow$ 評価エビデンス $\rightarrow$ 攻撃手法 $\rightarrow$ 被害影響」の多ホップ因果パス探索と、Ego Network による因果推論を可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連要求: [REQ-ONT-01](../../docs/requirements/REQ-ONT-01-security-paper-ontology.md)
- 設計仕様: [DSN-22](../../docs/designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 関連Issue: [Issue 184](184-enhance-owl-logic-incident-coupling-and-standards-alignment.md), [Issue 185](185-implement-threat-model-causality-impact-and-precondition-neutralization.md), [Issue 186](186-implement-claim-evidence-reification-and-regex-data-constraints.md), [Issue 187](187-implement-ontology-tbox-graph-ingestion-and-schema-view.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/ontology/schema.py](../../src/ontology/schema.py) (EntityType, Predicate, 新実体 dataclass 定義)
- [x] [src/ontology/extended_extractor.py](../../src/ontology/extended_extractor.py) (STRIDE Impact, Claims, Evaluation, Incidents 抽出)
- [x] [src/ontology/extractor.py](../../src/ontology/extractor.py) (OntologyExtractor ABox 結合)
- [x] [src/graph/engine.py](../../src/graph/engine.py) (PropertyGraphEngine 因果パス探索・クエリ拡張)
- [x] [tests/ontology/test_abox_causal_extraction.py](../../tests/ontology/test_abox_causal_extraction.py) (ABox 因果・具現化抽出単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/188-integrate-causal-reified-entities-into-paper-abox-graph`

1. **オントロジースキーマ拡張 (`src/ontology/schema.py`)**:
   - `EntityType` に `IMPACT`, `CLAIM`, `EVALUATION_RESULT` を追加。
   - `Predicate` に `HAS_IMPACT`, `NEUTRALIZES_PRECONDITION`, `EXPLOITED_IN`, `LEVERAGED_VULNERABILITY`, `ASSERTS_CLAIM`, `EVALUATES_TECHNIQUE`, `EVALUATES_CLAIM`, `YIELDS_EVALUATION` および各 inverse を追加。
   - `ImpactEntity`, `ClaimEntity`, `EvaluationResultEntity`, `IncidentEntity` の dataclass を定義。
2. **抽出エンジン拡張 (`src/ontology/extended_extractor.py`, `src/ontology/extractor.py`)**:
   - STRIDE 脅威モデルに基づく `Impact`（重大度 Severity、カテゴリ）の抽出ロジックを追加。
   - 防御策による前提条件無力化（`neutralizesPrecondition`）の抽出ロジックを追加。
   - 論文の主張具現化（`Claim`）および実験評価エビデンス（`EvaluationResult`、成功率・環境）の抽出ロジックを追加。
   - 実世界インシデント言及（`Incident`）の抽出と攻撃手法・脆弱性結合を追加。
3. **グラフDBエンジン＆可視化対応 (`src/graph/engine.py`)**:
   - `_format_cti_node` のカラーパレット（`Impact`: Pink, `Claim`: Violet, `EvaluationResult`: Mint Green）とノード半径を定義。
   - `_compute_cti_counts` での新実体集計の追加。
   - 多ホップ因果探索メソッド（`_query_causal`, `find_causal_chains`）の追加。
4. **テスト作成 & 検証**:
   - `tests/ontology/test_abox_causal_extraction.py` による抽出トリプル整合性・多ホップ因果探索の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/ontology/schema.py` に `Impact`, `Claim`, `EvaluationResult`, `Incident` および因果述語が追加されていること。
- [x] `ExtendedExtractor` および `OntologyExtractor` が新実体と因果トリプルを抽出できること。
- [x] `PropertyGraphEngine` にこれらが正常に格納され、4ホップ因果探索（Paper $\rightarrow$ Claim $\rightarrow$ EvaluationResult $\rightarrow$ AttackTechnique $\rightarrow$ Impact）が可能であること。
- [x] ユニットテスト `tests/ontology/test_abox_causal_extraction.py` が新規作成され、100% PASS すること。
- [x] 既存の全テスト（Pytest 83/83 passed, Black/Flake8 クリーン）が維持されていること。
