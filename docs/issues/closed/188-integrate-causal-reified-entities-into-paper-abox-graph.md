# Issue #188: 実論文データABoxへの新実体統合と因果・エビデンス探索の実装 (Task B)

## 1. 概要 (Overview)
Phase 1〜3（Issue #184, #185, #186）で策定した W3C OWL / Google OKF 準拠のセキュリティオントロジー `security_ontology_v2.ttl` (TBox) に基づき、実論文データ（ABox）の抽出・グラフインジェストパイプラインを拡張する。
論文の OKF メタデータおよび本文テキストから、被害影響（`Impact`）、攻撃前提条件の無力化（`neutralizesPrecondition`）、学術的主張（`Claim`）、実証評価結果（`EvaluationResult`）、および実世界インシデント（`Incident`）を自動抽出し、PropertyGraphEngine に ABox ノードおよび因果エッジとして格納する。
これにより、GraphRAG における「論文主張 $\rightarrow$ 評価エビデンス $\rightarrow$ 攻撃手法 $\rightarrow$ 被害影響」の多ホップ因果パス探索と、Ego Network による因果推論を可能にする。

## 2. 実装スコープ (Scope)
1. **オントロジースキーマ拡張 (`src/ontology/schema.py`)**:
   - `EntityType` に `IMPACT`, `CLAIM`, `EVALUATION_RESULT` を追加。
   - `Predicate` に `HAS_IMPACT`, `NEUTRALIZES_PRECONDITION`, `EXPLOITED_IN`, `LEVERAGED_VULNERABILITY`, `ASSERTS_CLAIM`, `EVALUATES_TECHNIQUE`, `EVALUATES_CLAIM`, `YIELDS_EVALUATION` およびそれらの `inverse` を追加。
   - `ImpactEntity`, `ClaimEntity`, `EvaluationResultEntity`, `IncidentEntity` の dataclass を定義。
2. **抽出エンジン拡張 (`src/ontology/extended_extractor.py`, `src/ontology/extractor.py`)**:
   - STRIDE脅威モデルに基づく `Impact`（重大度 Severity、カテゴリ）の抽出ロジックを追加。
   - 防御策による前提条件無力化（`neutralizesPrecondition`）の抽出ロジックを追加。
   - 論文の主張具現化（`Claim`）および実験評価エビデンス（`EvaluationResult`、成功率・環境）の抽出ロジックを追加。
   - 実世界インシデント言及（`Incident`）の抽出と攻撃手法・脆弱性結合を追加。
3. **グラフDBエンジン＆可視化対応 (`src/graph/engine.py`)**:
   - `_format_cti_node` のカラーパレット（`Impact`: Pink, `Claim`: Violet, `EvaluationResult`: Mint Green）とノード半径を定義。
   - `_compute_cti_counts` での新実体集計の追加。
   - 因果探索・パス追跡メソッド（GraphRAG 因果チェーン検索）の追加。
4. **テスト作成 (`tests/ontology/test_abox_causal_extraction.py`)**:
   - OKF テキストからの Impact / Claim / EvaluationResult / Incident 抽出と因果トリプルの整合性を検証。
   - PropertyGraphEngine へのインジェストと multi-hop 因果パス探索の動作検証。

## 3. 完了条件 (Definition of Done)
- [ ] `src/ontology/schema.py` に `Impact`, `Claim`, `EvaluationResult`, `Incident` および因果述語が追加されていること。
- [ ] `ExtendedExtractor` および `OntologyExtractor` が新実体と因果トリプルを抽出できること。
- [ ] `PropertyGraphEngine` にこれらが正常に格納され、4ホップ因果探索（Paper $\rightarrow$ Claim $\rightarrow$ EvaluationResult $\rightarrow$ AttackTechnique $\rightarrow$ Impact）が可能であること。
- [ ] ユニットテスト `tests/ontology/test_abox_causal_extraction.py` が新規作成され、100% PASS すること。
- [ ] 既存の全テスト（Pytest 83/83 passed, Black/Flake8 クリーン）が維持されていること。
