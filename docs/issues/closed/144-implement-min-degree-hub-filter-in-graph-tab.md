---
ID: 144
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] /dashboard tab=graph における最小次数フィルタ（Min-Degree / Hub Filter）の実装 (ID: 144)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph`（Knowledge & CTI Graph 専用ワークスペース）において、頂点のエッジ接続数（次数 $k$: degree）に応じた段階的な最小次数フィルタ（`Min Degree: All / ≥1 / ≥2 / ≥3`）を実装する。
エッジ数が少ない末端のリーフノードを段階的に非表示にし、多数の論文や脆弱性・攻撃手法を結びつける**ハブノード（コアネットワーク骨格）**を瞬時に抽出・分析できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - [Issue 140: ノード半径の面積比例スケーリング（R ∝ √(1+k)）](closed/140-scale-vertex-size-by-edge-degree.md)
  - [Issue 143: 孤立ノード（EdgeなしVertex）非表示トグル機能](143-implement-toggle-to-hide-isolated-nodes-in-graph-tab.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **DOM / 入力サニタイズ**: 次数選択はクライアント側で固定の数値列（0, 1, 2, 3, 5）に制限し、数値パース（`parseInt(val, 10)`）および境界値クランプ（`Math.max(0, val)`）を実施して予期しない文字列混入や NaN による計算エラーを防止する。
- **DoS / パフォーマンス保護**: フィルタリング処理は O(V + E) の Map 集計でミリ秒未満に完了させ、物理シミュレーション（Forces）の過負荷や UI フリーズを防止する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/144-implement-min-degree-hub-filter-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - `mesh-toolbar` 内（`ctiFilters` 領域の右側またはボタングループ）に、最小次数フィルタコントロールを配置:
     ```html
     <div style="display: flex; align-items: center; gap: 4px; border-left: 1px solid var(--border-dark); padding-left: 8px;">
       <span style="font-weight: 800; font-size: 11px;">MIN DEGREE:</span>
       <button id="btnDegAll" class="btn-tool active" onclick="setMinDegree(0)">All</button>
       <button id="btnDeg1" class="btn-tool" onclick="setMinDegree(1)">≥1</button>
       <button id="btnDeg2" class="btn-tool" onclick="setMinDegree(2)">≥2</button>
       <button id="btnDeg3" class="btn-tool" onclick="setMinDegree(3)">≥3</button>
     </div>
     ```
   - 各ボタンのクリック時に `.active` クラスを相互に切り替え。

2. **状態管理とフィルタリングロジック (`site/dashboard.html`)**:
   - 状態変数 `let minDegreeThreshold = 0;` を定義。
   - `window.setMinDegree(deg)` 関数を実装:
     - `minDegreeThreshold = Math.max(0, parseInt(deg, 10) || 0);`
     - ボタン群の `.active` クラスを更新。
     - 現在のモードに応じて `applyCtiFilter()` または `applyContextMesh()` を再実行。
   - `applyCtiFilter()`:
     - 現在の候補エッジ群から各ノードの次数 Map (`rawDegrees = new Map()`) を算出。
     - `if (minDegreeThreshold > 0)` の場合、`filteredNodes = filteredNodes.filter(n => (rawDegrees.get(n.id) || 0) >= minDegreeThreshold);` を適用。
     - 残存ノードに接続するエッジのみを `filteredEdges` に保持。
     - `graphQueryResultBadge` に「(最小次数 ≥${minDegreeThreshold}: ${filteredNodes.length}件)」を反映。
     - `updateNodeRadii(NODES, EDGES)` を呼び出し、フィルタ後のグラフ構造で頂点半径を整合再計算。
   - `applyContextMesh()`:
     - Context Mesh においても同様に `minDegreeThreshold` を適用し、ハブノードのみの俯瞰を可能にする。

3. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 に「11.8 最小次数フィルタ（Min-Degree Hub Filter）」を追記。

4. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_min_degree_hub_filter`:
     - `id="btnDegAll"`, `id="btnDeg1"`, `id="btnDeg2"`, `id="btnDeg3"` の存在確認。
     - `window.setMinDegree` 関数および `minDegreeThreshold` 状態変数の定義確認。
     - `applyCtiFilter` および `applyContextMesh` 内における `minDegreeThreshold` フィルタ処理の検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `site/dashboard.html` のツールバーに最小次数セレクター（All / ≥1 / ≥2 / ≥3）が配置されていること。
- [x] 選択した閾値未満のノードと孤立したエッジが即座に非表示になり、ハブ構造のみが可視化されること。
- [x] All（閾値 0）を選択すると元の全ノードが再描画されること。
- [x] クエリ探索および各種フィルタ（Papers / ATT&CK / CWE）と相互に干渉せず連動すること。
- [x] `tests/web/test_dashboard_graph_tab.py` の新規テストを含む全自動テストが 100% PASS すること。
- [x] 設計書 `DSN-14` に仕様が完全同期されていること。
