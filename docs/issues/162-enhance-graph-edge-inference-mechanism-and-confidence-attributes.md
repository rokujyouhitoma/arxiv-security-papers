---
ID: 162
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] グラフ Edge への推論・判定機構別確信度（Confidence & Inference Mechanism）属性の付与と高精度グラフ探索基盤の実装 (ID: 162)

## 1. 概要 / Summary
グラフデータベース（`src/graph/` PropertyGraphEngine）において、Paper 頂点と脅威（AttackTechnique）、脆弱性（CWE）、緩和策（DefenseMitigation）等を紐付ける有向 Edge に対し、単なる数値スコアに留まらず、**「どのような推論・判断機構（Inference Mechanism）に基づき、いかなる根拠（Evidence）と確信度（Confidence）で紐付けが決定されたか」**をメタデータ属性として厳密に保持・追跡可能にする。

これにより、確信度（confidence threshold）や推論手法（ルールベース、直接ID一致、語彙スコアリング、共起解析、LLMガードレール等）に応じた動的エッジフィルタリング、GraphRAG における高確信度エッジ優先走査、および `/dashboard tab=graph` での推論根拠の可視化を実現する。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - 先端知見統合と自律型分析プラットフォームのアーキテクチャ設計 (テーラーリング版 Phase 1)
  - `docs/issues/closed/160-implement-pure-python-stix-cti-inference-and-navigator-layer.md`
  - `src/graph/engine.py` (PropertyGraphEngine)
  - `src/graph/structures.py` (Edge, Vertex)
  - `src/domain/security/cti/graph_bridge.py` (sync_cti_inferences_to_graph)
  - `src/domain/security/cti/inference.py` (TechniqueInferenceEngine)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/domain/security/cti/graph_bridge.py](file:///workspace/arxiv-security-papers/src/domain/security/cti/graph_bridge.py): Edge 作成時の推論機構・根拠・確信度メタデータ属性の完全記録
- [ ] [src/domain/security/cti/inference.py](file:///workspace/arxiv-security-papers/src/domain/security/cti/inference.py): 推論判定機構（`mechanism: str`）およびスコア内訳・エビデンス（`evidence: Dict`）の構造化出力
- [ ] [src/graph/structures.py](file:///workspace/arxiv-security-papers/src/graph/structures.py): Edge 構造体における確信度・推論機構ヘルパーメソッドの拡充
- [ ] [src/graph/engine.py](file:///workspace/arxiv-security-papers/src/graph/engine.py): 確信度閾値（min_confidence）および判定機構（mechanism）によるエッジ走査・フィルタリングAPI
- [ ] [src/graph/traversal.py](file:///workspace/arxiv-security-papers/src/graph/traversal.py): 確信度重み付け対応グラフ走査
- [ ] [tests/domain/test_edge_confidence.py](file:///workspace/arxiv-security-papers/tests/domain/test_edge_confidence.py): 判定機構・確信度属性の永続化とクエリ検証単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/162-edge-inference-mechanism-confidence`

1. **Edge メタデータ属性体系の標準化**:
   - `edge.weight: float`（確信度スコア 0.0 〜 1.0）
   - `edge.properties`:
     - `confidence: float`: 確信度（0.0 〜 1.0）
     - `inference_mechanism: str`: 判定機構種別
       - `"regex_direct_id"`: 論文テキスト中に直接 Technique ID (例: T1190) を検知（確信度 1.0）
       - `"title_exact_keyword"`: タイトルにおける手法名・重要キーワード一致（確信度 0.8〜0.9）
       - `"abstract_semantic_scoring"`: アブストラクト・本文の専門語彙マッチング（確信度 0.4〜0.7）
       - `"heuristic_cooccurrence"`: 関連共起語彙・オントロジー推論
       - `"catalog_curated"`: 既知カタログ・シグネチャ照合
     - `mechanism_version: str`: 推論エンジンバージョン（例: `"rule_v1.0"`, `"catalog_attack_v14"`)
     - `evidence: Dict[str, Any]`: 判定根拠（一致語彙一覧、出現位置、各スコア加算要素）
     - `timestamp: str`: 判定・紐付け実行の ISO 8601 UTC タイムスタンプ
     - `evaluator: str`: 評価モジュール名（`TechniqueInferenceEngine` 等）
2. **TechniqueInferenceEngine の高度化**:
   - `InferredTechnique` に `inference_mechanism: str`, `mechanism_version: str`, `evidence: Dict[str, Any]` を追加
   - 推論時にどの判定ロジックでスコアが算出されたかを構造化して返却
3. **Graph Bridge (`graph_bridge.py`) の連携拡張**:
   - `sync_cti_inferences_to_graph` が上記メタデータを Edge の `properties` に完全格納
4. **Graph Engine & Traversal での確信度フィルタリング**:
   - `get_out_edges` / `get_in_edges` / 探索クエリにおいて `min_confidence` や `allowed_mechanisms` によるフィルタリングをサポート

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Paper と AttackTechnique 等を紐付ける全 Edge に `confidence`, `inference_mechanism`, `evidence`, `timestamp` 属性が付与されること
- [ ] `TechniqueInferenceEngine` が判定機構（直接ID一致、タイトル語彙、要約語彙スコアリング等）を識別して出力すること
- [ ] グラフエンジンにおいて特定確信度以上（例: `confidence >= 0.8`）や特定判定機構（例: `mechanism == "regex_direct_id"`）のエッジのみを絞り込み走査可能であること
- [ ] 既存のグラフ永続化および単体テストがすべて正常動作すること
- [ ] 新規単体テストが 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (xenon Rank A, mypy --strict) が 100% PASS すること
