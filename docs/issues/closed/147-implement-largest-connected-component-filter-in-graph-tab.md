---
ID: 147
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT] /dashboard tab=graph における最大連結成分（LCC: Largest Connected Component）抽出機能の実装 (ID: 147)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、グラフ内の最大連結成分（Largest Connected Component: 最もノード数が多く相互接続されている主要クラスタ）のみを抽出し、2〜3ノードだけで孤立している周辺の「離れ小島クラスタ」を一括非表示にする「LCC 抽出トグル機能」を実装する。
マクロな全体ネットワークのコア構造をクリアに俯瞰できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - [Issue 143: 孤立ノード（EdgeなしVertex）非表示トグル機能](143-implement-toggle-to-hide-isolated-nodes-in-graph-tab.md)
  - [Issue 144: 最小次数フィルタ（Min-Degree / Hub Filter）の実装](144-implement-min-degree-hub-filter-in-graph-tab.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **DoS / 再帰スタックオーバーフロー保護**: 連結成分の探索において、再帰的 DFS は深いコールスタックで `RangeError: Maximum call stack size exceeded` を引き起こす危険があるため、反復的 BFS（キューを用いたループ処理）または Union-Find 木を実装し、ノード数が数千件に肥大化してもブラウザが絶対にクラッシュしない堅牢性を確保する。
- **ゼロ除外ガード**: エッジが 0 本の場合や全ノードが孤立している場合に空集合で描画がフリーズしないよう、フォールバックガードを設ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/147-implement-largest-connected-component-filter-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - コントロールデッキ内（`btnToggleIsolated` の隣）に「メイン成分 (LCC)」ボタンを配置:
     ```html
     <button id="btnToggleLcc" class="btn-tool" onclick="toggleLccOnly()" data-tooltip="最大連結成分（最も多くのノードが接続された主要クラスタ）のみを表示します" data-tooltip-pos="bottom">メイン成分 (LCC)</button>
     ```
   - アクティブ時に `.active` クラスを付与。

2. **連結成分解析アルゴリズム (BFS) と状態管理 (`site/dashboard.html`)**:
   - 状態変数 `let filterLccOnly = false;` を新設。
   - `window.toggleLccOnly()` 関数:
     - `filterLccOnly = !filterLccOnly;` をトグル。
     - ボタン要素の表示スタイルを更新。
     - 現在のモードに応じて `applyCtiFilter()` または `applyContextMesh()` を再実行。
   - `computeLargestConnectedComponent(nodes, edges)` 関数:
     - 隣接リスト（`adj = new Map()`）を構築。
     - 未訪問ノード群から反復的 BFS で連結成分（ノード ID 配列）を順次クラスタリング。
     - 最も要素数の多い成分のノード ID 集合（`Set<string>`）を返却。ノードが 0 件の場合は空 Set を返却。
   - `applyCtiFilter()` および `applyContextMesh()`:
     - `if (filterLccOnly)` の場合、上記関数で得られた LCC ノード集合に属するノードのみを `filteredNodes` に残す。
     - 両端が LCC ノード集合に含まれるエッジのみを `filteredEdges` に残す。
     - `graphQueryResultBadge` に「(LCC: ${filteredNodes.length} ノード抽出)」を表示。
     - `updateNodeRadii(NODES, EDGES)` を呼び出し、LCC 内部での頂点次数・半径を正確に再計算。

3. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 に「11.11 最大連結成分（LCC: Largest Connected Component）抽出機能」を追記。

4. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_largest_connected_component_filter`:
     - `id="btnToggleLcc"` の存在確認。
     - `toggleLccOnly` 関数および `filterLccOnly` 状態変数の定義確認。
     - 反復的 BFS による LCC 抽出ロジックの存在確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] ツールバーに「🌐 メイン成分 (LCC)」ボタンが配置されていること。
- [x] ボタン押下で、最大連結成分以外の小規模クラスタが即座に非表示になり、主要ネットワークのみが画面中央に残ること。
- [x] 再度押下すると全クラスタが元の位置関係を維持して復元されること。
- [x] 非連結グラフや孤立ノード群に対してもコールスタックエラーを起こさず安全に動作すること。
- [x] `tests/web/test_dashboard_graph_tab.py` の新規テストを含む全自動テストが 100% PASS すること。
- [x] 設計書 `DSN-14` に仕様が完全同期されていること。

