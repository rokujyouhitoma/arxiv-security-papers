---
ID: 143
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] /dashboard tab=graph における孤立ノード（EdgeなしVertex）非表示トグル機能の実装 (ID: 143)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、エッジ（接続関係）を持たない次数0の頂点（Isolated Nodes: degree = 0）を非表示にするトグル機能（「🔗 孤立ノード除外」）を実装した。
これにより、クエリ検索時や全域メッシュ探索時において、関係性を持たない頂点群による視覚ノイズを排除し、論文・攻撃手法・脆弱性・防御メカニズムの密結合な因果関係ネットワークに集中して分析・可視化を行えるようにした。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace / Section 11.7)
- 関連Issue:
  - [Issue 138: /dashboard における専用 Knowledge & CTI Graph 画面の実装](138-add-dedicated-graph-engineering-tab-in-dashboard.md)
  - [Issue 139: レイアウト再設計と要素重複の解消](139-fix-graph-workspace-layout-and-overlap.md)
  - [Issue 140: エッジ接続数に応じた頂点サイズ（Vertex Size）のスケーリング](140-scale-vertex-size-by-edge-degree.md)
  - [Issue 142: バックグラウンド Live Mesh 同期によるサブグラフ上書き防止](142-fix-graph-query-subgraph-reset-by-background-sync.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/143-implement-toggle-to-hide-isolated-nodes-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - `mesh-toolbar` 右側のボタングループ（`margin-left: auto`）に、「🔗 孤立ノード除外」トグルボタン（`id="btnToggleIsolated"`）を追加配置。
   - ボタンのアクティブ状態に応じて `.active` クラスをトグルし、ボタンテキストを `🔗 孤立ノード除外 (ON)` / `🔗 孤立ノード除外` に切り替え。
   - ツールチップ (`title="エッジを持たない孤立頂点 (degree = 0) を非表示にします"`) を付与。

2. **状態管理とフィルタリングロジック (`site/dashboard.html`)**:
   - 状態変数 `let hideIsolatedNodes = false;` を新設。
   - `window.toggleIsolatedNodes()` 関数を実装:
     - `hideIsolatedNodes = !hideIsolatedNodes;` をトグル。
     - ボタン要素の表示および `.active` クラスを更新。
     - 現在のモードに応じて `applyCtiFilter()` または `applyContextMesh()` を再実行。
   - `applyCtiFilter()`:
     - `filteredEdges` の抽出後、`if (hideIsolatedNodes)` の場合にエッジ接続先・接続元に存在するノードIDの集合（`connectedIds`）を作成。
     - `filteredNodes = filteredNodes.filter(n => connectedIds.has(n.id));` を適用。
     - 除外された孤立ノード数をログ出力またはステータス表示で可視化。
   - Context Mesh (`syncLiveMesh` / `applyContextMesh`):
     - `contextRawNodes` / `contextRawEdges` をキャッシュ管理し、Context Mesh 表示時にも `hideIsolatedNodes` が有効な場合はエッジを持たないノードをフィルタリングして物理シミュレーションに渡す。
   - `updateNodeRadii(NODES, EDGES)` との完全協調:
     - 孤立ノード除外後、残存した接続ノード群のみで次数に応じた頂点サイズ計算（Min 6px〜Max 32px）が正確に維持される。

3. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_toggle_hide_isolated_nodes`:
     - `site/dashboard.html` 内に `id="btnToggleIsolated"` が存在すること。
     - `toggleIsolatedNodes` 関数が定義されており、`hideIsolatedNodes` の真偽値が切り替わること。
     - `applyCtiFilter` 内で `hideIsolatedNodes` に基づく孤立ノード（degree = 0）除外処理が存在すること。
     - 全自動テスト (`pytest tests/web/`) が全件 PASS すること。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `site/dashboard.html` のツールバーに「🔗 孤立ノード除外」ボタンが配置されていること。
- [x] ボタンをクリックするとトグル動作し、エッジを持たない孤立ノード（degree = 0）が即座に非表示になること。
- [x] 再度クリックすると元の全ノード（孤立ノードを含む）が表示されること。
- [x] クエリ探索中（`match: side-channel` 等）でも孤立ノード除外トグルが正常に連動すること。
- [x] Context Mesh および CTI Graph の両モードで整合して機能すること。
- [x] 新規単体テストを含む全自動テスト (`pytest tests/web/`)、型検査 (`mypy --strict`)、複雑度解析 (`xenon`) を 100% PASS すること。

