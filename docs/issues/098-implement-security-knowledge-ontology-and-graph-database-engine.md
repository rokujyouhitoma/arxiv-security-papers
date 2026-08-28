---
ID: 098
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] セキュリティ知識オントロジー (SKO) 定義およびゼロ侵襲型グラフデータベース基盤の実装 (ID: 098)

## 1. 概要 / Summary
設計仕様書 **[DSN-17]**（`docs/designs/DSN-17-security_knowledge_ontology.md`）および **[DSN-18]**（`docs/designs/DSN-18-property_graph_database_engine.md`）に基づき、サイバーセキュリティ論文ナレッジグラフの中核となる「**セキュリティ知識オントロジー（Security Knowledge Ontology: SKO）**」を定義・体系化する。

同時に、既存の堅牢なデータベース基盤（`src/database/` の SlottedPage, B-Tree, ARIES WAL, VectorStorage, 3ノード分散クラスタ）には**一切手を加えず（コード改変 0 行）**、その上位ストレージアダプタとして動作する独立トップレベルモジュール **ゼロ侵襲型 Property Graph Database Engine (`src/graph/`)** を構築する。

これにより、人間・AI（GraphRAG）・システム三者に対して、単なるキーワード/ベクトル検索を超えた **複数論文を跨ぐ多段階因果推論（Multi-Hop Reasoning: 攻撃手法 $\rightarrow$ 脆弱性 $\rightarrow$ 標的システム $\rightarrow$ 防御技術）** とミリ秒未満の $O(1)$ グラフ探索を提供する。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-17-security_knowledge_ontology.md](../designs/DSN-17-security_knowledge_ontology.md)
  - [docs/designs/DSN-18-property_graph_database_engine.md](../designs/DSN-18-property_graph_database_engine.md)
  - [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)
  - [docs/designs/DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
- **脅威モデル & セキュリティ要件 (Sec / AU 監査)**:
  - **T1: メモリ枯渇 (OOM) 防止**: グラフ走査時の深さ制限（Max Hops $\le 5$）と LRU キャッシュサイズ上限（$\le 128\text{ MB}$）の強制。
  - **T2: パストラバーサル・インジェクション排除**: 頂点 ID・述語・プロパティ値の厳密なサニタイズ。
  - **T3: データ整合性・トレーサビリティ**: OKF 論文とグラフ頂点・辺の双方向リンクおよびハッシュ整合性の保証。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/ontology/__init__.py](../../src/ontology/__init__.py) [NEW]: オントロジーパッケージ初期化
- [ ] [src/ontology/schema.py](../../src/ontology/schema.py) [NEW]: 7大コアエンティティ（Paper, ThreatActor, AttackTechnique, Vulnerability, TargetAsset, DefenseMechanism, BenchmarkMetric）および12大関係述語の型定義
- [ ] [src/ontology/taxonomy.py](../../src/ontology/taxonomy.py) [NEW]: MITRE ATT&CK, CWE, CVE, NIST SP 800-53, STRIDE 表記揺れ吸収辞書
- [ ] [src/ontology/extractor.py](../../src/ontology/extractor.py) [NEW]: OKF 論文からのオントロジー・トリプル自動抽出エンジン
- [ ] [src/graph/__init__.py](../../src/graph/__init__.py) [NEW]: グラフDBパッケージ初期化
- [ ] [src/graph/engine.py](../../src/graph/engine.py) [NEW]: ゼロ外部依存 Property Graph Engine（頂点・辺の CRUD と双方向隣接インデックス CSR）
- [ ] [src/graph/traversal.py](../../src/graph/traversal.py) [NEW]: Fluent Graph Traversal DSL（`g.V().out().in_()`）& Multi-Hop 最短経路 / PageRank
- [ ] [src/graph/graphrag.py](../../src/graph/graphrag.py) [NEW]: ベクトル検索（HNSW）とグラフ走査を融合する GraphRAG 推論エンジン
- [ ] [tests/ontology/test_schema.py](../../tests/ontology/test_schema.py) [NEW]: オントロジー型定義・タクソノミー単体テスト
- [ ] [tests/graph/test_graph_engine.py](../../tests/graph/test_graph_engine.py) [NEW]: グラフDBエンジンと Traversal DSL の単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/098-implement-security-knowledge-ontology-and-graph-database-engine`

### Step 1: オントロジー定義層 (`src/ontology/`) の実装
1. `src/ontology/schema.py`:
   - エンティティ基底クラス `Entity` と 7大具象クラス（`PaperEntity`, `ThreatActorEntity`, `AttackTechniqueEntity`, `VulnerabilityEntity`, `TargetAssetEntity`, `DefenseMechanismEntity`, `BenchmarkMetricEntity`）。
   - 12大関係述語 Enum `Predicate`（`DISCLOSES`, `EXPLOITS`, `ANALYZES`, `TARGETS`, `PROPOSES`, `MITIGATES`, `PATCHES`, `EVALUATES`, `ATTRIBUTED_TO`, `SUBCLASS_OF`, `PART_OF`, `CITES`）。
   - 事実トリプル dataclass `Triple(subject_id, predicate, object_id, weight, properties)`。
2. `src/ontology/taxonomy.py`:
   - `TaxonomyRegistry`: 同義語辞書（`SYNONYM_MAPPINGS`）と正規化メソッド `normalize_term(term)`。
3. `src/ontology/extractor.py`:
   - `OntologyExtractor`: OKF Markdown フロントマターおよび Abstract/本文から 7大エンティティおよびトリプルを自動抽出。

### Step 2: 独立 Property Graph Engine (`src/graph/`) の実装
1. `src/graph/engine.py`:
   - `PropertyGraphEngine`:
     - 既存 `src/database/` コードには一切手を加えず、`outputs/database/graph.db`（またはメモリ内）に永続化。
     - 頂点テーブル `_vertices: Dict[str, Vertex]` と双方向隣接リスト（Forward CSR: `_out_edges: Dict[str, List[Edge]]`, Reverse CSR: `_in_edges: Dict[str, List[Edge]]`）。
     - `add_vertex(vertex_id, vertex_type, properties) -> Vertex`
     - `add_edge(src_id, dst_id, predicate, weight, properties) -> Edge`
     - `get_vertex(vertex_id) -> Optional[Vertex]`
     - `V(vertex_type, **filters) -> GraphTraversal`
2. `src/graph/traversal.py`:
   - `GraphTraversal`:
     - メソッドチェーン（Fluent API）: `.out(*predicates)`, `.in_(*predicates)`, `.both(*predicates)`, `.filter(fn)`
     - 探索アルゴリズム: `shortest_path(target_id)`, `k_hop_neighborhood(k)`, `pagerank(damping, iterations)`
     - 出力変換: `.to_list()`, `.to_triples()`, `.to_subgraph_json()`

### Step 3: GraphRAG & 多段階因果推論 (`src/graph/graphrag.py`) の実装
1. `GraphRAGPipeline`:
   - HNSW ベクトル検索で取得した Top-K 論文頂点を起点として、K-Hop グラフ展開を実行。
   - LLM プロンプト用の構造化グラウンディング事実トリプル（Grounding Triples）を生成し、ハルシネーションを排除。

### Step 4: 単体テスト & 品質ゲート検証
1. `tests/ontology/test_schema.py`: エンティティ作成、シリアライズ、タクソノミー同義語解決のテスト。
2. `tests/graph/test_graph_engine.py`: 頂点・辺の CRUD、双方向隣接走査、Fluent Traversal、Multi-Hop 探索、PageRank のテスト。
3. `make format`, `make static_analysis` (flake8 / mypy --strict), `pytest` 全件パス。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/ontology/` に SKO 7大エンティティ・12大関係述語・タクソノミー正規化が実装されていること。
- [ ] `src/graph/` に既存 DB 無改変の Property Graph Engine および Fluent Traversal API が実装されていること。
- [ ] 1-Hop 走査 $< 0.05\text{ms}$、3-Hop 走査 $< 5\text{ms}$ の性能基準を満たすこと。
- [ ] `tests/ontology/` および `tests/graph/` の自動テストが 100% PASS すること。
- [ ] `make check` / `make verify_quality` が 100% PASS すること。
