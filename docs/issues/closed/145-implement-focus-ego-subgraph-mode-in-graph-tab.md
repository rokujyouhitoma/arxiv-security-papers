---
ID: 145
種別: Feature
優先度: Medium
ステータス: Closed (Done)
---

# [FEAT] /dashboard tab=graph における特定ノードのフォーカス・エゴネットワーク抽出機能の実装 (ID: 145)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、任意のノードをダブルクリック、またはサイドインスペクター（`#nodeCallout`）から「🎯 フォーカス (Ego 2-Hop)」ボタンを押下した際に、**その中心ノードから 1〜2 ホップ以内の直接関係ノード・エッジのみを強調表示し、無関係なノードをディミング（透明度 0.08 に減衰）または一時除外**する「エゴネットワーク（Ego Subgraph）フォーカス機能」を実装する。
膨大なグラフの中から、特定の論文や攻撃手法の因果関係チェーンに完全に集中して探索できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - [Issue 137: グラフクエリ・コンソール（`ego: <node> <depth>` サポート）](closed/137-implement-graph-query-console-and-subgraph-extraction-in-dashboard.md)
  - [Issue 138: 専用 Graph タブの実装](closed/138-create-dedicated-graph-tab-in-dashboard.md)
  - [Issue 139: レイアウト再設計と Drawer 配置](closed/139-redesign-graph-tab-layout-and-fix-element-overlapping.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **DOM / XSS 防止**: フォーカス対象のノード ID やタイトルをインスペクターやバッジに反映する際、`textContent` またはエスケープ済みヘルパーを使用し、悪意あるタイトル文字列による DOM XSS を完全に防御する。
- **グラフ探索保護 (BFS Loop Guard)**: エゴネットワーク計算において、訪問済みノードを `Set` で厳密に追跡し、循環参照（ループグラフ）による無限ループ・スタックオーバーフローを防止する。ホップ数上限を最大 3 に固定（クランプ）する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/145-implement-focus-ego-subgraph-mode-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - サイドインスペクター Drawer (`#nodeCallout`) の下部アクションエリアに「🎯 エゴ抽出 (2-Hop)」ボタンを追加:
     ```html
     <button id="btnFocusEgo" class="btn-callout-action" onclick="focusCurrentSelectedEgo()">🎯 このノードにフォーカス (2-Hop)</button>
     ```
   - ツールバー（`mesh-toolbar`）にフォーカス状態インジケーターと解除ボタンを追加:
     ```html
     <div id="focusBanner" style="display: none; align-items: center; gap: 6px; background: rgba(59, 130, 246, 0.15); border: 1px solid #3B82F6; padding: 2px 8px; border-radius: 4px; font-size: 11px;">
       <span>🎯 フォーカス中: <strong id="focusTargetLabel">-</strong></span>
       <button id="btnClearFocus" class="btn-tool" onclick="clearNodeFocus()" title="フォーカスを解除して全域表示に戻す">✕ 解除</button>
     </div>
     ```

2. **インタラクションと状態管理 (`site/dashboard.html`)**:
   - 状態変数:
     - `let focusedNodeId = null;`
     - `let focusedHopNodeIds = null;` (Set of IDs)
   - キャンバスダブルクリックイベント (`dblclick`):
     - クリック座標にある頂点を検出し、存在すれば `focusEgoNetwork(node.id, 2)` を実行。
   - キャンバス空白クリック:
     - 頂点以外の空白部分がクリックされた場合、または「✕ 解除」ボタン押下時に `clearNodeFocus()` を実行。

3. **エゴ探索アルゴリズム (BFS) と描画処理**:
   - `getEgoNeighborhood(centerId, depth = 2)`:
     - `EDGES` を探索し、1ホップ隣接ノードおよび2ホップ隣接ノードを `Set` に収集。
   - `render()` 描画ループの適応:
     - `focusedHopNodeIds` が非 null の場合:
       - 対象外ノード: `ctx.globalAlpha = 0.08` でフェードアウト描画（または完全非表示）。
       - 対象ノード: 通常不透明度で描画し、中心ノードには青色パルス外枠 (`ctx.arc(..., r + 4)`) を追加。
       - 対象外エッジ: 非表示または `ctx.globalAlpha = 0.05`。
       - 対象エッジ: 鮮明に描画。
   - `graphQueryResultBadge` に「🎯 エゴ展開: 中心 [ID] (関連 ${focusedHopNodeIds.size} ノード)」を表示。

4. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 に「11.9 エゴネットワーク（Ego Subgraph）フォーカス機能」を追記。

5. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_focus_ego_subgraph_mode`:
     - `id="btnFocusEgo"`, `id="btnClearFocus"`, `id="focusBanner"` の存在確認。
     - `focusEgoNetwork` および `clearNodeFocus` 関数の定義確認。
     - ダブルクリックハンドラーまたはクリックイベント連動の検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] ノード詳細 Drawer に「🎯 このノードにフォーカス」ボタンが配置されていること。
- [x] ノードのダブルクリックまたはボタン押下で、該当ノードから2ホップ以内のエゴサブグラフのみがクローズアップ表示され、他ノードがフェードアウトすること。
- [x] ツールバーに「✕ 解除」ボタンが表示され、クリックまたは背景クリックで通常表示へ即座に復帰すること。
- [x] 循環グラフ構造でも BFS が安全に停止しブラウザがフリーズしないこと。
- [x] `tests/web/test_dashboard_graph_tab.py` の新規テストを含む全自動テストが 100% PASS すること。
- [x] 設計書 `DSN-14` に仕様が完全同期されていること。

