---
ID: 146
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] /dashboard tab=graph におけるエッジ関係性（Relation Type）個別フィルタ機能の実装 (ID: 146)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、CTI ナレッジグラフのエッジ関係性（`EXPLOITS`, `MITIGATES`, `DISCLOSES`, `SUBCLASS_OF` 等）を個別にトグルで表示/非表示にできる「エッジ関係性フィルタ」を実装する。
「防御メカニズム（`MITIGATES`）の関係チェーンだけを追跡したい」「脆弱性の悪用関係（`EXPLOITS`）のみに絞り込みたい」といった具体的な分析目的に応じて、特定タイプのエッジおよびその接続サブグラフを抽出・比較できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - [Issue 135: CTI ナレッジグラフデータ基盤およびインタラクティブ可視化の実装](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
  - [Issue 138: 専用 Graph タブの実装](closed/138-create-dedicated-graph-tab-in-dashboard.md)
  - [Issue 140: ノード半径の面積比例スケーリング](closed/140-scale-vertex-size-by-edge-degree.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **プロトタイプ汚染防止 (Prototype Pollution Guard)**: リレーションキーのオン/オフ更新において、`Object.prototype` や組み込みキーの汚染を防ぐため、許可されたホワイトリスト（`ALLOWED_RELATIONS = ['EXPLOITS', 'MITIGATES', 'DISCLOSES', 'SUBCLASS_OF']`）による厳格なバリデーションを実施する。
- **レンダリング整合性**: エッジ種別が無効化された場合でも、エッジ配列のインデックス参照や物理シミュレーション（Link distance / Spring force）が破綻しないよう、クリーンな配列再構築を担保する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/146-implement-edge-relation-type-filter-in-graph-tab`

1. **凡例 / ツールバー連携 UI の拡張 (`site/dashboard.html`)**:
   - `ctiLegend`（左上の CTI 凡例）内に、DSN-21 および Issue #182 準拠の絵文字を排除したクリック可能なエッジ関係性トグルチップを配置:
     ```html
     <div class="legend-relations-row" style="display: flex; gap: 4px; margin-top: 8px; flex-wrap: wrap;">
       <button id="btnRelExploits" class="btn-rel-chip active" onclick="toggleEdgeRelation('EXPLOITS')" data-tooltip="EXPLOITS 関係のエッジを表示/非表示"><span class="rel-indicator rel-exploits"></span>EXPLOITS</button>
       <button id="btnRelMitigates" class="btn-rel-chip active" onclick="toggleEdgeRelation('MITIGATES')" data-tooltip="MITIGATES 関係のエッジを表示/非表示"><span class="rel-indicator rel-mitigates"></span>MITIGATES</button>
       <button id="btnRelDiscloses" class="btn-rel-chip active" onclick="toggleEdgeRelation('DISCLOSES')" data-tooltip="DISCLOSES 関係のエッジを表示/非表示"><span class="rel-indicator rel-discloses"></span>DISCLOSES</button>
       <button id="btnRelSubclass" class="btn-rel-chip active" onclick="toggleEdgeRelation('SUBCLASS_OF')" data-tooltip="SUBCLASS_OF 関係のエッジを表示/非表示"><span class="rel-indicator rel-subclass"></span>SUBCLASS</button>
     </div>
     ```
   - トグル状態に応じて `.active` クラスおよびボタンスタイル（不透明度・枠線）を更新。

2. **状態管理とエッジフィルタリングロジック (`site/dashboard.html`)**:
   - 状態オブジェクト:
     ```javascript
     const ALLOWED_RELATIONS = ['EXPLOITS', 'MITIGATES', 'DISCLOSES', 'SUBCLASS_OF'];
     const activeEdgeRelations = {
       EXPLOITS: true,
       MITIGATES: true,
       DISCLOSES: true,
       SUBCLASS_OF: true
     };
     ```
   - `window.toggleEdgeRelation(relType)` 関数:
     - ホワイトリスト検証を行い、`activeEdgeRelations[relType] = !activeEdgeRelations[relType]` をトグル。
     - チップ要素の `.active` クラスを更新。
     - `applyCtiFilter()` を再実行。
   - `applyCtiFilter()`:
     - `ctiRawEdges` から、`activeEdgeRelations[e.label || e.rel] !== false` を満たすエッジのみを抽出。
     - 抽出された `filteredEdges` をもとに、ノードの接続状態や次数を再計算。
     - `updateNodeRadii(NODES, EDGES)` を呼び出し、残存エッジ関係性に応じた頂点サイズを動的に再計算。

3. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 に「11.10 エッジ関係性（Relation Type）個別フィルタ機能」を追記。

4. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_edge_relation_type_filter`:
     - `id="btnRelExploits"`, `id="btnRelMitigates"`, `id="btnRelDiscloses"`, `id="btnRelSubclass"` の存在確認。
     - `toggleEdgeRelation` 関数および `activeEdgeRelations` オブジェクトの定義確認。
     - `applyCtiFilter` 内におけるリレーション別エッジ除外処理の検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] CTI 凡例またはツールバーに各エッジ種別（EXPLOITS, MITIGATES, DISCLOSES, SUBCLASS_OF）のトグルチップが配置されていること。
- [x] 特定の関係性をオフにすると、該当する種類のエッジが即座に非表示になり、物理シミュレーションからも安全に除外されること。
- [x] 再度オンにするとエッジが復元されること。
- [x] 孤立ノード非表示トグル (`hideIsolatedNodes`) や次数フィルタ (`minDegreeThreshold`) と完全に協調動作すること。
- [x] `tests/web/test_dashboard_graph_tab.py` の新規テストを含む全自動テストが 100% PASS すること。
- [x] 設計書 `DSN-14` に仕様が完全同期されていること。

