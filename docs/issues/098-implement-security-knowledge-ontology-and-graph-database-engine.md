---
ID: 098
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] セキュリティ知識オントロジー (SKO) 定義およびゼロ侵襲型グラフデータベース基盤の実装 (ID: 098)

## 1. 概要 / Summary
設計仕様書 **[DSN-17]**（`docs/designs/DSN-17-security_knowledge_ontology_and_graph_database_engine.md`）に基づき、サイバーセキュリティ論文ナレッジグラフの中核となる「**セキュリティ知識オントロジー（Security Knowledge Ontology: SKO）**」を定義・体系化する。

同時に、既存の堅牢なデータベース基盤（`src/database/` の SlottedPage, B-Tree, ARIES WAL, VectorStorage, 3ノード分散クラスタ）には**一切手を加えず（コード改変 0 行）**、その上位ストレージアダプタとして動作する **ゼロ侵襲型 Property Graph Database Engine (`src/database/graph/`)** を構築する。

これにより、人間・AI（GraphRAG）・システム三者に対して、単なるキーワード/ベクトル検索を超えた **複数論文を跨ぐ多段階因果推論（Multi-Hop Reasoning: 攻撃手法 $\rightarrow$ 脆弱性 $\rightarrow$ 標的システム $\rightarrow$ 防御技術）** とミリ秒未満の $O(1)$ グラフ探索を提供する。

---

## 2. トレーサビリティ & 脅威モデル / Traceability & Threat Model
- **関連資料**:
  - [docs/designs/DSN-17-security_knowledge_ontology_and_graph_database_engine.md](../designs/DSN-17-security_knowledge_ontology_and_graph_database_engine.md)
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
- [ ] [src/database/graph/__init__.py](../../src/database/graph/__init__.py) [NEW]: グラフDBパッケージ初期化
- [ ] [src/database/graph/engine.py](../../src/database/graph/engine.py) [NEW]: ゼロ外部依存 Property Graph Engine（頂点・辺の CRUD と双方向隣接インデックス CSR）
- [ ] [src/database/graph/traversal.py](../../src/database/graph/traversal.py) [NEW]: Fluent Graph Traversal DSL（`g.V().out().in_()`）& Multi-Hop 最短経路 / PageRank
- [ ] [src/database/graph/graphrag.py](../../src/database/graph/graphrag.py) [NEW]: ベクトル検索（HNSW）とグラフ走査を融合する GraphRAG 推論エンジン
- [ ] [tests/ontology/test_schema.py](../../tests/ontology/test_schema.py) [NEW]: オントロジー型定義・タクソノミー単体テスト
- [ ] [tests/database/graph/test_graph_engine.py](../../tests/database/graph/test_graph_engine.py) [NEW]: グラフDBエンジンと Traversal DSL の単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/098-implement-security-knowledge-ontology-and-graph-database-engine`

1. **オントロジー定義層 (`src/ontology/`) の構築**:
   - 7大エンティティと 12 大関係述語を Pure Python Typed Dataclass / Enum として定義。
   - MITRE ATT&CK / CWE / STRIDE / NIST SP 800-53 の同義語正規化マッピングテーブルを配備。
2. **ゼロ侵襲型 Property Graph Engine (`src/database/graph/`) の構築**:
   - 既存 DB コードには一切手を加えず、専用のバイナリ隣接インデックス（CSR / Double Adjacency List）ストレージアダプタを実装。
   - メモリ内 L1 キャッシュとディスク永続化（`outputs/database/graph.db`）をシームレスに統合。
3. **Fluent Traversal API & GraphRAG 基盤の実装**:
   - 直感的なメソッドチェーンによる Multi-Hop グラフ探索 DSL を実装。
   - ベクトル検索で取得した Top-K 論文を起点とする K-Hop グラフ展開と事実トリプル生成。
4. **テスト & 品質ゲート検証**:
   - `pytest tests/ontology/ tests/database/graph/`, `make format`, `make static_analysis` (flake8/mypy) 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/ontology/` に SKO 7大エンティティ・12大関係述語・タクソノミー正規化が実装されていること。
- [ ] `src/database/graph/` に既存 DB 無改変の Property Graph Engine および Fluent Traversal API が実装されていること。
- [ ] 1-Hop 走査 $< 0.05\text{ms}$、3-Hop 走査 $< 5\text{ms}$ の性能基準を満たすこと。
- [ ] `tests/ontology/` および `tests/database/graph/` の自動テストが 100% PASS すること。
- [ ] `make check` / `make verify_quality` が 100% PASS すること。
