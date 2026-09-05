---
ID: 162
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] グラフ Edge への判断ルール・推論機構・確信度・エビデンス属性の統合付与と高精度グラフ探索基盤の実装 (ID: 162)

## 1. 概要 / Summary
グラフデータベース（`src/graph/` PropertyGraphEngine）において、Paper 頂点と脅威（AttackTechnique）、脆弱性（CWE）、緩和策（DefenseMitigation）等を紐付ける有向 Edge に対し、単なる数値スコアに留まらず、**「どのルール（Rule ID/Name）に基づき、いかなる推論機構（Inference Mechanism）、根拠エビデンス（Evidence/Matched Terms/Snippets）、確信度区分（Confidence Tier）、および入力データ整合性ハッシュ」**で紐付けが決定されたかをメタデータ属性として厳密に保持・追跡可能にする。

これにより、以下の実務的ユースケースを実現する：
1. **説明可能性（Explainability & Traceability）**: なぜその論文が特定の手法（T1190等）と紐づいているのか、マッチしたルール・単語・出現箇所（タイトル/要約）をエッジ属性から即座に監査可能にする。
2. **高精度フィルタリング走査**: 「確信度 HIGH のみ」「正規表現直接一致ルール（RULE-TECH-REGEX）で判定されたエッジのみ」「査読済みエッジのみ」といった条件付きグラフ走査・Ego-network 抽出を可能にする。
3. **GraphRAG における推論信頼度重み付け**: ナレッジグラフを介したマルチホップ推論において、ルールの信頼性スコアや確信度をエッジ重みとして動的反映し、幻覚（Hallucination）を抑制する。
4. **再評価・無効化のライフサイクル管理**: 論文テキストが更新された際、`source_text_hash` との差分比較により、古いルールのエッジを差分再推論・更新可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - 先端知見統合と自律型分析プラットフォームのアーキテクチャ設計 (テーラーリング版 Phase 1)
  - `docs/designs/DSN-07-security_guard_and_rbac.md` (Rev 2.2)
  - `docs/issues/closed/160-implement-pure-python-stix-cti-inference-and-navigator-layer.md`
  - `src/graph/engine.py` (PropertyGraphEngine, Dual CSR Adjacency Index)
  - `src/graph/structures.py` (Edge, Vertex)
  - `src/domain/security/cti/graph_bridge.py` (sync_cti_inferences_to_graph)
  - `src/domain/security/cti/inference.py` (TechniqueInferenceEngine)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Model & Security Requirements)
1. **推論メタデータの耐改ざん性・一貫性保証**:
   - エッジメタデータに判定日時、評価器バージョン、入力テキストの SHA-256 ハッシュ（先頭16文字）を付与し、事後的な追跡とデータ改ざん検知を可能にする。
2. **入力テキストの安全なエスケープ**:
   - マッチしたエビデンス（スニペット）をエッジプロパティに含める際、制御文字・改行文字を安全に正規化し、グラフシリアライズ時の JSON/辞書インジェクションを防止する。
3. **過剰検知（False Positive）の隔離制御**:
   - 低確信度（`confidence < 0.5`）のエッジには `confidence_tier = "LOW"` を明示し、デフォルトの探索クエリや GraphRAG 走査から安全に除外できるようにする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/domain/security/cti/inference.py`: 推論判定ルール定義（Rule Registry）、エビデンス構造体、ルールID・スコア内訳・入力ハッシュの算出
- [ ] `src/domain/security/cti/graph_bridge.py`: Edge 作成時におけるルールメタデータ、エビデンス、確信度区分の完全属性格納
- [ ] `src/graph/structures.py`: Edge クラスへの確信度・ルール照会ヘルパーメソッド (`is_high_confidence()`, `has_rule()`) の追加
- [ ] `src/graph/engine.py`: `get_out_edges` / `get_in_edges` における `min_confidence`, `min_tier`, `allowed_rules`, `allowed_mechanisms` フィルタ引数のサポート
- [ ] `src/domain/security/cti/__init__.py`: 新規エクスポート（ルール定義、ConfidenceTier等）の追加
- [ ] `tests/domain/test_edge_confidence.py`: ルール属性付与、エビデンス追跡、フィルタリング走査の単体テスト

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/162-edge-inference-mechanism-confidence`

### 5.1 判断ルール（Rule）およびエビデンス構造体の設計 (`inference.py`)
- **推論ルール体系の定義**:
  - `RULE-TECH-REGEX-DIRECT-01`: 論文本文・タイトルから Technique ID 正規表現（`T\d{4}(?:\.\d{3})?`）を直接検知（確信度 1.0, Mechanism: `"regex_direct_id"`）
  - `RULE-TECH-TITLE-NAME-02`: タイトルに Technique 名が完全一致（確信度 0.8, Mechanism: `"title_exact_keyword"`）
  - `RULE-TECH-TITLE-KEYWORD-03`: タイトルに主要キーワードが一致（確信度 0.5, Mechanism: `"title_keyword"`）
  - `RULE-TECH-ABSTRACT-KEYWORD-04`: アブストラクトに専門語彙・同義語が一致（確信度 0.25〜0.5, Mechanism: `"abstract_semantic_scoring"`）
  - `RULE-FOCUS-OFFENSIVE-01`: 攻撃系キーワード優勢による攻防判定（Edge: `TARGETS`）
  - `RULE-FOCUS-DEFENSIVE-02`: 防御系キーワード優勢による攻防判定（Edge: `PROPOSES_DEFENSE`）
  - `RULE-FOCUS-ANALYSIS-03`: 攻防中立・一般分析（Edge: `DISCUSSES`）

- **`InferenceEvidence` データクラス**:
  ```python
  @dataclass(frozen=True)
  class InferenceEvidence:
      rule_id: str
      rule_name: str
      rule_category: str  # pattern, lexical, contextual
      matched_terms: List[str]
      target_field: str  # title, abstract, combined
      score_contribution: float
      snippet: str = ""
  ```

- **`InferredTechnique` の拡張**:
  - `applied_rules: List[str]`: 適用されたルールID一覧
  - `primary_rule_id: str`: 最も寄与度の高い主判定ルールID
  - `inference_mechanism: str`: 主推論機構識別子
  - `evidences: List[InferenceEvidence]`: 各ルールの判定エビデンス一覧
  - `confidence_tier: str`: `"HIGH"` ($\ge 0.8$), `"MEDIUM"` ($0.5 \le c < 0.8$), `"LOW"` ($< 0.5$)
  - `source_text_hash: str`: 入力テキストの SHA-256 先頭 16 桁

### 5.2 Edge 属性体系の標準化と永続化 (`graph_bridge.py`)
- Paper と Technique を結ぶ `Edge(src_id, dst_id, label, weight, properties)` の属性体系：
  - `weight`: `float(round(confidence, 4))`
  - `properties`:
    - `confidence`: `float`
    - `confidence_tier`: `"HIGH" | "MEDIUM" | "LOW"`
    - `primary_rule_id`: `str` (例: `"RULE-TECH-REGEX-DIRECT-01"`)
    - `applied_rules`: `List[str]`
    - `inference_mechanism`: `str` (例: `"regex_direct_id"`)
    - `mechanism_version`: `"2026.09.v1"`
    - `evaluator`: `"TechniqueInferenceEngine"`
    - `evaluator_version`: `"1.0.0"`
    - `evidences`: `List[Dict[str, Any]]` (各ルールのマッチ語彙、寄与スコア、スニペット)
    - `source_text_hash`: `str`
    - `research_focus`: `"offensive" | "defensive" | "analysis"`
    - `focus_rule_id`: `"RULE-FOCUS-OFFENSIVE-01"` 等
    - `semantic_rationale`: `str`
    - `timestamp`: `str` (ISO 8601 UTC)
    - `validation_status`: `"inferred"`

### 5.3 Edge クラスヘルパーの拡充 (`src/graph/structures.py`)
- `Edge.is_high_confidence(threshold: float = 0.8) -> bool`
- `Edge.has_rule(rule_id: str) -> bool`
- `Edge.get_confidence() -> float`

### 5.4 Graph Engine 走査 API の条件絞り込み拡張 (`src/graph/engine.py`)
- `get_out_edges(vertex_id, *labels, min_confidence: Optional[float] = None, min_tier: Optional[str] = None, allowed_rules: Optional[List[str]] = None, allowed_mechanisms: Optional[List[str]] = None) -> List[Edge]`
- `get_in_edges(...)` にも同様のフィルタリングを実装。
- `find_papers_for_technique` / `find_techniques_for_paper` において `min_confidence` や `rule_id` による絞り込みパラメータを追加。

### 5.5 制約・品質保証
- **外部依存ゼロ**: Python 標準ライブラリ (`hashlib`, `datetime`, `re`, `typing`, `dataclasses`) のみ使用。
- **Xenon 循環的複雑度**: 全新規・変更関数 $\le 5$ (Rank A 必須)。
- **Mypy `--strict` 適合**: 全 402+ ファイルで 0 エラー維持。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `TechniqueInferenceEngine` が推論時に `applied_rules`, `primary_rule_id`, `evidences`, `confidence_tier`, `source_text_hash` を正しく生成すること
- [ ] `graph_bridge.py` が生成された推論メタデータを `PropertyGraphEngine` の Edge properties に完全格納・永続化できること
- [ ] Edge properties から判定ルールID、一致語彙、スコア寄与度、入力テキストハッシュが正確に逆引き・監査可能であること
- [ ] `PropertyGraphEngine.get_out_edges` / `get_in_edges` で `min_confidence`, `min_tier`, `allowed_rules` を指定した絞り込み走査が正常に機能すること
- [ ] 確信度区分（`HIGH`, `MEDIUM`, `LOW`）によるフィルタリングが正しく動作すること
- [ ] 単体テスト `tests/domain/test_edge_confidence.py` を作成し、100% PASS すること
- [ ] 既存の全単体テスト（`tests/domain/test_stix_navigator.py` 等）が互換性を保ち 100% PASS すること
- [ ] `make check_format` および `make static_analysis` (radon, xenon Rank A, flake8, mypy --strict) が 100% PASS すること
