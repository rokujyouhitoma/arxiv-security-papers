---
ID: 143
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] /dashboard tab=graph における孤立ノード（EdgeなしVertex）非表示トグル機能の実装 (ID: 143)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、エッジ（接続関係）を持たない次数0の頂点（Isolated Nodes: degree = 0）を非表示にするトグル機能（「🔗 孤立ノード除外」）を実装する。
これにより、クエリ検索時や全域メッシュ探索時において、関係性を持たない頂点群による視覚ノイズを排除し、論文・攻撃手法・脆弱性・防御メカニズムの密結合な因果関係ネットワークに集中して分析・可視化を行えるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 138: `/dashboard` における専用 Knowledge & CTI Graph 画面の実装
  - Issue 139: レイアウト再設計と要素重複の解消
  - Issue 140: エッジ接続数に応じた頂点サイズ（Vertex Size）のスケーリング
  - Issue 142: バックグラウンド Live Mesh 同期によるサブグラフ上書き防止

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)
- [ ] [docs/designs/DSN-14-graph_engineering_dashboard.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/143-implement-toggle-to-hide-isolated-nodes-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - `mesh-toolbar` のフィルター領域（`ctiFilters`）およびツールバーに、「🔗 孤立ノード除外 (Hide Isolated)」トグルボタン（`id="btnToggleIsolated"`）を配置。
   - ボタンのアクティブ状態に応じてスタイル（背景ハイライトおよびテキスト表示 `🔗 孤立ノード除外 (ON)` / `🔗 孤立ノード除外`）を切り替え。
   - Context Mesh モードおよび CTI Graph モードの双方で一貫して機能するように配置・連携。

2. **状態管理とフィルタリングロジック**:
   - 状態変数 `let hideIsolatedNodes = false;` を追加。
   - `window.toggleIsolatedNodes()` 関数を実装：
     - `hideIsolatedNodes = !hideIsolatedNodes;` をトグル。
     - ボタンのクラス・スタイルを更新。
     - `applyCtiFilter()` または `applyCurrentGraphFilter()` を再発火してグラフ再計算。
   - `applyCtiFilter()` および Context Mesh のノード構築ロジックにおいて：
     - 各ノードのエッジ接続数（degree）を算出し、`hideIsolatedNodes === true` の場合は `degree === 0` のノードを `NODES` から除外。
     - エッジが存在するノードのみで Force-directed layout 物理シミュレーションと Canvas 描画を実行。
   - クエリ結果バッジやステータス表示において、除外ノード数をユーザーにわかりやすく明示（例: `✅ 12 件一致 (孤立 5 件除外)`）。

3. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `btnToggleIsolated` 要素の存在確認。
   - `hideIsolatedNodes` 状態変数および `toggleIsolatedNodes` 関数の定義検証。
   - degree = 0 のノードが `hideIsolatedNodes` 有効時にフィルタリングされるロジックの静的・振る舞い検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/dashboard.html` のツールバーに「🔗 孤立ノード除外」ボタンが配置されていること。
- [ ] ボタンをクリックするとトグル動作し、エッジを持たない孤立ノード（degree = 0）が即座に非表示になること。
- [ ] 再度クリックすると元の全ノード（孤立ノードを含む）が表示されること。
- [ ] クエリ探索中（`match: side-channel` 等）でも孤立ノード除外トグルが正常に連動すること。
- [ ] 新規単体テストを含む全自動テスト (`pytest tests/web/`)、型検査 (`mypy --strict`)、複雑度解析 (`xenon`) を 100% PASS すること。
