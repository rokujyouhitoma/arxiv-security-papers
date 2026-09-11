---
ID: 250
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/CORE] CTI 脅威知識グラフにおける Louvain 法（モジュラリティ最適化）コミュニティ検出および攻撃キャンペーンクラスタリングの実装 (ID: 250)

## 1. 概要 / Summary

本 Issue では、CTI（Cyber Threat Intelligence）知識グラフ（脅威アクター、マルウェアファミリ、MITRE ATT&CK 手法、CWE/CVE 等）における攻撃キャンペーンクラスタや類似脅威グループを高精度に自動抽出するため、モジュラリティ最大化（Modularity Optimization）に基づく **Pure-Python Louvain コミュニティ検出アルゴリズム** を `src/core/structures/` に実装し、`src/graph/`（`GraphEngine` / `GraphTraversal`）へ統合する。

直近の Issue #247 で導入された `DisjointSet`（Union-Find）はグラフの「完全孤立した連結成分」の分離に有効である一方、現実の CTI 知識グラフは多くのエンティティが間接的に接続されて単一の巨大連結成分（Giant Component）を形成しやすい。そのため、エッジの重みや接続密度に基づいてグラフ内部の密結合サブグラフを分割・識別できるコミュニティ検出アルゴリズムが必要不可欠となる。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-14-graph_engineering_dashboard.md`](../designs/DSN-14-graph_engineering_dashboard.md) (Graph Analytics & Subgraph Extraction)
  - [`docs/designs/DSN-18-property_graph_database_engine.md`](../designs/DSN-18-property_graph_database_engine.md) (Graph Traversal & Graph Algorithms)
- **先行 Issue**:
  - [Issue #247: Disjoint Set (Union-Find) の共通コア実装](closed/247-implement-disjoint-set-union-find-for-graph-clustering.md)
  - [Issue #147: Largest Connected Component Filter in Graph Tab](closed/147-implement-largest-connected-component-filter-in-graph-tab.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/community.py`](../../src/core/structures/community.py) (新規: Louvain 法およびモジュラリティ計算エンジン)
- [ ] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py) (公開エクスポートの追加)
- [ ] [`src/graph/traversal.py`](../../src/graph/traversal.py) (コミュニティ検出インターフェース `detect_communities()` の追加)
- [ ] [`src/graph/engine.py`](../../src/graph/engine.py) (グラフエンジンからのコミュニティ分割・クラスタ属性付与)
- [ ] [`tests/core/test_community.py`](../../tests/core/test_community.py) (新規: コミュニティ検出単体テスト)
- [ ] [`tests/graph/test_graph_traversal.py`](../../tests/graph/test_graph_traversal.py) (グラフ走査結合テスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/250-implement-louvain-community-detection-for-cti-graph`

1. **共通コアアルゴリズムの実装 (`src/core/structures/community.py`)**:
   - ゼロ外部依存（Pure Python 標準ライブラリのみ）で重み付き無向グラフに対する Louvain コミュニティ検出を実装。
   - フェーズ 1: 各ノードを自身のコミュニティに初期化し、近傍コミュニティへの移動に伴うモジュラリティ利得 $\Delta Q$ を貪欲（Greedy）に評価・最大化。
   - フェーズ 2: 検出されたコミュニティをスーパーノードに縮約したメタグラフを構築し、モジュラリティの増加が閾値以下になるまで反復。
2. **`src/core/structures/__init__.py` への統合**:
   - `LouvainCommunityDetector` または `detect_louvain_communities()` をエクスポート。
3. **`src/graph/` への統合**:
   - `GraphTraversal` に `detect_communities(resolution: float = 1.0, weight_property: Optional[str] = None) -> Dict[str, int]` メソッドを追加。
   - CTI グラフノードに対して検出されたコミュニティ ID を付与し、攻撃キャンペーン・脅威クラスタごとのサブグラフ抽出を可能にする。
4. **テストスイートの作成**:
   - Clique（完全グラフ）グラフ、Zachary's Karate Club 等の標準トポロジーでのクラスタ分離検証。
   - モジュラリティ値 $Q \in [-0.5, 1.0]$ の計算検証、エッジ重みの考慮、決定論的シード/順序保証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/core/structures/community.py` にゼロ外部依存で Louvain 法コミュニティ検出が実装されていること。
- [ ] `src/graph/traversal.py` からコミュニティ検出 API が利用可能であること。
- [ ] `tests/core/test_community.py` および `tests/graph/` のテストが全件 PASS すること。
- [ ] `make py_compile` および `make static_analysis` (mypy, flake8) がエラー 0 件で通過すること。
