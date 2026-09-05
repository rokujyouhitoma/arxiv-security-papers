---
ID: 162
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] グラフ Edge への判断ルール・推論機構・確信度・エビデンス属性の統合付与と高精度グラフ探索基盤の実装 (ID: 162)

## 1. 概要 / Summary
グラフデータベース（`src/graph/` PropertyGraphEngine）において、Paper 頂点と脅威（AttackTechnique）、脆弱性（CWE）、緩和策（DefenseMitigation）等を紐付ける有向 Edge に対し、単なる数値スコアに留まらず、**「どのルール（Rule ID/Name）に基づき、いかなる推論機構（Inference Mechanism）、根拠エビデンス（Evidence/Matched Terms/Snippets）、確信度区分（Confidence Tier）、および入力データ整合性ハッシュ」**で紐付けが決定されたかをメタデータ属性として厳密に保持・追跡可能にする。

これは、先行して完了した **EIROM（Issue 163: Edge Inference Rule Ontology Master）** の推論ルール公理を、実グラフ Edge プロパティへ刻印（Inscribe）し、以下の実務的ユースケースを実現するものである：
1. **説明可能性（Explainability & Traceability）**: なぜその論文が特定の手法（T1190等）と紐づいているのか、マッチしたルール・単語・出現箇所（タイトル/要約）をエッジ属性から即座に監査可能にする。
2. **高精度フィルタリング走査**: 「確信度 HIGH のみ」「正規表現直接一致ルール（RULE-EDGE-PAPER-TECH-REGEX-01）で判定されたエッジのみ」といった条件付きグラフ走査・Ego-network 抽出を可能にする。
3. **GraphRAG における推論信頼度重み付け**: ナレッジグラフを介したマルチホップ推論において、ルールの信頼性スコアや確信度をエッジ重みとして動的反映し、幻覚（Hallucination）を抑制する。
4. **再評価・無効化のライフサイクル管理**: 論文テキストが更新された際、`source_text_hash` との差分比較により、古いルールのエッジを差分再推論・更新可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (Rev 2.0 Section 6 & 11: 動的エッジ説明責任とEIROM仕様)
  - `docs/designs/DSN-18-property_graph_database_engine.md`
  - `docs/issues/closed/163-implement-edge-inference-rule-ontology-master.md` (EIROM 基盤)
  - `docs/issues/closed/160-implement-pure-python-stix-cti-inference-and-navigator-layer.md`
  - `src/graph/engine.py` (PropertyGraphEngine, Dual CSR Adjacency Index)
  - `src/graph/structures.py` (Edge, Vertex)
  - `src/domain/security/cti/graph_bridge.py` (sync_cti_inferences_to_graph)
  - `src/domain/security/cti/inference.py` (TechniqueInferenceEngine)
  - `src/ontology/rule_registry.py` (EdgeInferenceRuleRegistry)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **推論メタデータの耐改ざん性・一貫性保証**:
   - エッジメタデータに判定日時（ISO 8601 UTC）、評価器バージョン、入力テキストの SHA-256 ハッシュ（先頭16文字）を付与し、事後的な追跡とデータ改ざん検知を可能にする。
2. **入力テキストの安全なエスケープ**:
   - マッチしたエビデンス（スニペット・引用）をエッジプロパティに含める際、制御文字・改行文字を安全に正規化し、グラフシリアライズ時の JSON/辞書インジェクションや破損を防止する。
3. **過剰検知（False Positive）の隔離制御**:
   - 低確信度（`confidence < 0.5`）のエッジには `confidence_tier = "LOW"` を明示し、デフォルトの探索クエリや GraphRAG 走査から安全に除外できるようにする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/domain/security/cti/inference.py`: `InferenceEvidence` データクラス、`InferredTechnique` へのエビデンス・推論機構・確信度ティア・テキストハッシュ・引用スニペットの格納
- [ ] `src/domain/security/cti/graph_bridge.py`: Edge 作成時における完全な説明責任メタデータ（ルールID、推論機構、エビデンス、確信度ティア、テキストハッシュ、タイムスタンプ）の永続化
- [ ] `src/graph/structures.py`: Edge クラスへの確信度・ルール照会ヘルパーメソッド (`get_confidence()`, `get_confidence_tier()`, `is_high_confidence()`, `has_rule()`, `get_primary_rule()`, `get_evidences()`) の追加
- [ ] `src/graph/engine.py`: `get_out_edges` / `get_in_edges` における `min_confidence`, `min_tier`, `allowed_rules`, `allowed_mechanisms` フィルタ引数のサポート
- [ ] `src/domain/security/cti/__init__.py`: 新規エクスポート（`InferenceEvidence` 等）の追加
- [ ] `tests/domain/test_edge_confidence.py`: ルール属性付与、エビデンス追跡、フィルタリング走査の単体テスト

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/162-edge-inference-mechanism-confidence`

### 5.1 エビデンス構造体と推論エンジン出力拡張 (`inference.py`)
- **`InferenceEvidence` データクラス (`frozen=True`)**:
  - `rule_id: str`: 適用ルールID（例: `"RULE-EDGE-PAPER-TECH-REGEX-01"`）
  - `rule_name: str`: ルール表示名
  - `rule_category: str`: ルール種別（`"pattern"`, `"lexical"`, `"semantic_threshold"`, `"context_ratio"`）
  - `matched_terms: List[str]`: マッチした語彙・IDリスト
  - `target_field: str`: 対象フィールド（`"title"`, `"abstract"`, `"combined"`）
  - `score_contribution: float`: 寄与確信度スコア
  - `snippet: str`: 根拠テキストスニペット（最大 120 文字正規化）
  - `to_dict() -> Dict[str, Any]` / `from_dict(cls, data)` シリアライザ
- **`InferredTechnique` の拡張**:
  - `applied_rules: List[str]`: 適用ルールIDリスト
  - `primary_rule_id: Optional[str]`: 主判定ルールID
  - `inference_mechanism: str`: 主推論機構識別子（`"regex_direct_id"`, `"title_exact_keyword"`, `"title_keyword"`, `"abstract_semantic_scoring"`）
  - `evidences: List[InferenceEvidence]`: 構造化エビデンスリスト
  - `confidence_tier: str`: `"HIGH"`, `"MEDIUM"`, `"LOW"`
  - `source_text_hash: str`: 入力テキストの SHA-256 先頭 16 文字
  - `evidence_quote: str`: UI 表示用 primary スニペット

### 5.2 Edge クラスヘルパーの拡充 (`src/graph/structures.py`)
- `Edge.get_confidence() -> float`: `properties["confidence"]` または `self.weight`
- `Edge.get_confidence_tier() -> str`: `"HIGH"` ($\ge 0.8$), `"MEDIUM"` ($\ge 0.5$), `"LOW"` ($< 0.5$)
- `Edge.is_high_confidence(threshold: float = 0.8) -> bool`: 閾値判定
- `Edge.has_rule(rule_id: str) -> bool`: `primary_rule_id` または `applied_rules` 内のマッチ照合
- `Edge.get_primary_rule() -> Optional[str]`: 主ルールID取得
- `Edge.get_evidences() -> List[Dict[str, Any]]`: エビデンスリスト取得

### 5.3 Graph Engine 走査 API の条件絞り込み拡張 (`src/graph/engine.py`)
- `get_out_edges(vertex_id, *labels, min_confidence=None, min_tier=None, allowed_rules=None, allowed_mechanisms=None) -> List[Edge]`
- `get_in_edges(...)` にも同様のフィルタリングを実装。
- 補助関数 `_filter_edge_confidence` および `_filter_edge_rules` により Xenon Rank A ($\le 5$) を厳格遵守。
- `find_papers_for_technique` / `find_techniques_for_paper`（`graph_bridge.py`）に `min_confidence` や `rule_id` フィルタを追加。

### 5.4 Edge 属性体系の標準化と永続化 (`graph_bridge.py`)
- `_add_technique_vertex_and_edge` における `edge_props` 構造：
  ```python
  {
      "confidence": round(tech.confidence, 4),
      "confidence_tier": tech.confidence_tier,
      "primary_rule_id": tech.primary_rule_id,
      "applied_rules": tech.applied_rules,
      "inference_mechanism": tech.inference_mechanism,
      "mechanism_version": "2026.09.v1",
      "evaluator": "TechniqueInferenceEngine",
      "evaluator_version": "1.0.0",
      "evidences": [e.to_dict() for e in tech.evidences],
      "source_text_hash": tech.source_text_hash,
      "evidence_quote": tech.evidence_quote,
      "research_focus": tech.research_focus,
      "keywords": tech.matched_keywords,
      "timestamp": datetime.now(timezone.utc).isoformat(),
      "validation_status": "inferred",
  }
  ```

### 5.5 制約・品質保証
- **外部依存ゼロ**: Python 標準ライブラリ (`hashlib`, `datetime`, `re`, `typing`, `dataclasses`) のみ使用。
- **Xenon 循環的複雑度**: 全新規・変更関数 $\le 5$ (Rank A 必須)。
- **Mypy `--strict` 適合**: 全ソースファイルで 0 エラー維持。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `TechniqueInferenceEngine` が推論時に `applied_rules`, `primary_rule_id`, `inference_mechanism`, `evidences`, `confidence_tier`, `source_text_hash`, `evidence_quote` を正しく生成すること
- [ ] `graph_bridge.py` が生成された推論メタデータを `PropertyGraphEngine` の Edge properties に完全格納・永続化できること
- [ ] `Edge` クラスのヘルパーメソッド（`get_confidence`, `get_confidence_tier`, `is_high_confidence`, `has_rule` 等）が期待通り動作すること
- [ ] `PropertyGraphEngine.get_out_edges` / `get_in_edges` で `min_confidence`, `min_tier`, `allowed_rules`, `allowed_mechanisms` を指定した絞り込み走査が正常に機能すること
- [ ] 確信度区分（`HIGH`, `MEDIUM`, `LOW`）によるフィルタリングが正しく動作すること
- [ ] 単体テスト `tests/domain/test_edge_confidence.py` を作成し、100% PASS すること
- [ ] 既存の全単体テスト（`tests/domain/test_stix_navigator.py` 等）が互換性を保ち 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (radon, xenon Rank A, flake8, mypy --strict) が 100% PASS すること

