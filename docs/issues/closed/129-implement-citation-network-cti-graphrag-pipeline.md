---
ID: 129
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 論文引用ネットワークとCTIナレッジグラフを統合したマルチホップGraphRAGパイプラインの実装 (ID: 129)

## 1. 概要 / Summary
収集された STIX / CTI 脅威知識グラフ（`:AttackTechnique`, `:Vulnerability`, `:DefenseMechanism`）と論文間の引用関係（Citation Network: `[:CITES]`）を同一のインメモリプロパティグラフ基盤（`PropertyGraphEngine`）上で完全統合し、有向多重グラフに対するマルチホップ走査および PageRank 重要度順位付けを行う GraphRAG パイプラインを Pure Python（ゼロ外部依存）で実装する。

特定の攻撃手法（例: ATT&CK T1059）や脆弱性クラス（例: CWE-787）をシード（起点）として入力した際、その脆弱性を実証・悪用した論文群から引用関係を前方・後方へ辿り、派生攻撃の発展推移や、それらに対抗する形式検証・自動修復パッチを提案した最新防御論文群を 2〜4 ホップ走査で高速特定し、ハルシネーション（幻覚）ゼロの根拠サブグラフ付きコンテキストを合成する。

---

## 2. トレーサビリティ / Traceability
- [DSN-18: ゼロ侵襲型 Property Graph Database Engine](../../docs/designs/DSN-18-property_graph_database_engine.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-RES-01, UC-RES-02, UC-NCO-04)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 135: arXivセキュリティ論文・MITRE ATT&CK・CWEナレッジグラフデータ基盤](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
- [Issue 136: Context Meshにおけるエンティティ名寄せ・重複排除](closed/136-implement-context-mesh-entity-resolution-and-deduplication.md)
- [src/graph/engine.py](../../src/graph/engine.py)
- [src/graph/graphrag.py](../../src/graph/graphrag.py)
- [src/graph/traversal.py](../../src/graph/traversal.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-129-01: 相互引用・閉路（Cyclic References）による再帰探索スタックオーバーフロー**
  - *脅威*: 論文 A が論文 B を引用し、論文 B が論文 A のプレプリントを引用するような循環依存が存在する場合、深さ優先探索で無限ループや RecursionError が発生する。
  - *対策*: 訪問済み集合（`visited: Set[str]`）による厳格な重複訪問排除、および深さ上限（`max_depth=4`）の強制適用。
- **T-129-02: 高密度ハブ論文の展開によるサブグラフ爆発 (Graph Explosion DoS)**
  - *脅威*: 多数の論文から引用される古典的・基礎的論文（ハブノード）を展開した際、隣接エッジが数千件に膨れ上がり、メモリとシリアライズを圧迫する。
  - *対策*: ノードごとの展開次数上限（`max_neighbors_per_hop=30`）およびサブグラフ全体の上限ノード数（`max_subgraph_nodes=200`）を設け、PageRank スコアの高い上位エッジを優先展開。
- **T-129-03: PageRank 収束ループにおける非接続・孤立ノードの確率消失 (Dangling Node Trap)**
  - *脅威*: 出次数 0 のリーフノードに確率質量が吸い取られ、PageRank スコアが 0 に縮退して適切な重要度判定ができなくなる。
  - *対策*: ダンピングファクター $d = 0.85$ および出次数 0 ノードの均等再配分（Teleportation）を Pure Python で忠実に実装。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/graph/citation_linker.py` (論文本文およびメタデータからの引用 arXiv ID 抽出・エッジ構築器)
- [x] `src/graph/graphrag.py` (引用ネットワーク対応 GraphRAG パイプライン本体)
- [x] `src/graph/traversal.py` (PageRank 計算アルゴリズムおよびマルチホップ双方向走査エンジン)
- [x] `src/graph/structures.py` (Citation エッジ属性および拡張プロパティの検証)
- [x] `tests/graph/test_citation_graphrag.py` (マルチホップ推論、引用探索、PageRank 収束単体テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/129-implement-citation-network-cti-graphrag-pipeline`

1. **ステップ 1: 引用リンク抽出器の実装 (`src/graph/citation_linker.py`)**:
   - `CitationLinker` クラスを実装。OKF ドキュメントおよび Raw テキスト内の arXiv 形式 ID（例: `arXiv:2301.12345`, `2402.99999`）を決定論的正規表現で走査。
   - 実在する論文頂点（`:Paper`）同士を `[:CITES]` エッジで結合（方向: 引用元 $\rightarrow$ 引用先）。
2. **ステップ 2: PageRank アルゴリズムの実装 (`src/graph/traversal.py`)**:
   - 外部ライブラリ（NetworkX, NumPy）を使用せず、有向グラフに対するべき乗法（Power Iteration）を標準 `math` / `dict` のみで実装。
   - パラメータ: `damping=0.85`, `max_iter=50`, `tolerance=1e-6`。
   - 各頂点の中心性スコア（Importance）を事前算出し、グラフ走査時のプライオリティキューのキーとして利用。
3. **ステップ 3: マルチホップ統合 GraphRAG パイプライン (`src/graph/graphrag.py`)**:
   - `GraphRAGPipeline.query_attack_evolution(technique_id: str, max_depth: int = 3) -> Dict[str, Any]` を追加。
   - 探索フロー:
     1. `:AttackTechnique` に接続する `:Paper` ノード群を逆引き（`[:EXPLOITS]` / `[:ANALYZES]`）。
     2. 引用エッジ `[:CITES]` を前後に辿り、先行研究および発展研究を収集。
     3. 収集された論文群から `[:PROPOSES]` されている `:DefenseMechanism` を抽出。
     4. 得られたサブグラフから事実トリプル（Subject, Predicate, Object）を組み立て、コンテキストプロンプトを合成。
4. **ステップ 4: テストスイートと品質検証**:
   - `tests/graph/test_citation_graphrag.py` で既知の攻撃（例: T1059）起点での 3-Hop 探索シナリオ、PageRank 収束性、閉路耐性をテスト。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 引用エッジ `[:CITES]` と CTI リレーションが 1 つのグラフ構造内で矛盾なく統合走査できること
- [x] 攻撃テクニック起点のマルチホップ走査（深さ 3）が 50 ミリ秒以内で完了すること
- [x] 閉路（循環引用）が存在するグラフ構造でもスタックオーバーフローや無限ループに陥らないこと
- [x] 外部依存ゼロ（標準ライブラリのみ）で PageRank アルゴリズムが正しく収束し、重要ノードの順位が算出されること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
