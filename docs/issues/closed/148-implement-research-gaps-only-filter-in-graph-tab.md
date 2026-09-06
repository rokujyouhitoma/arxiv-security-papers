---
ID: 148
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] /dashboard tab=graph における未研究・未対策脅威（Research Gaps Only）専用絞り込みフィルタの実装 (ID: 148)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、現在の「⚡ Highlight Gaps（オレンジ枠ハイライト）」トグルに加え、**学術論文による防御・分析がまだ存在しない攻撃手法や脆弱性（Research Gap ノード: `is_research_gap === true`）のみを画面内にワンクリックで絞り込む「🚨 Gaps のみ (Gaps Only)」フィルタ**を実装する。
未解決のセキュリティ脅威や、今後学術・産業界で研究開発が求められる未開拓領域（ブルーオーシャン）を即座に一覧・抽出・構造分析できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md) (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - [Issue 135: CTI ナレッジグラフと Research Gaps 解析](closed/135-implement-paper-attck-cwe-knowledge-graph-and-dashboard-visualization.md)
  - [Issue 137: `gaps` プリセットクエリの実装](closed/137-implement-graph-query-console-and-subgraph-extraction-in-dashboard.md)
  - [Issue 138: 専用 Graph タブの実装](closed/138-create-dedicated-graph-tab-in-dashboard.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [site/dashboard.html](../../site/dashboard.html)
- [tests/web/test_dashboard_graph_tab.py](../../tests/web/test_dashboard_graph_tab.py)
- [docs/designs/DSN-14-graph_engineering_dashboard.md](../designs/DSN-14-graph_engineering_dashboard.md)

---

## 4. セキュリティ考慮事項 / Security Analysis
- **脅威データ整合性 (Threat Gap Integrity)**: `is_research_gap` フラグはバックエンド（`PropertyGraphEngine`）から供給される信頼されたメタデータに基づいて評価され、クライアント側でのフィルタリングによる偽陽性・偽陰性の発生を防止する。
- **UI 表示の安定性**: Gaps ノードのみに絞り込んだ結果ノード数が 0 件、またはエッジが 0 本（全ノードが次数0）となる場合でも、描画ループや物理シミュレーションが安全に動作する境界値ガードを設ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/148-implement-research-gaps-only-filter-in-graph-tab`

1. **UI 拡張 (`site/dashboard.html`)**:
   - `ctiFilters` 領域の「⚡ Highlight Gaps」ボタンの隣に、DSN-21 / Issue #182 準拠の「Gaps のみ」ボタンを追加配置:
     ```html
     <button id="btnFilterGapsOnly" class="btn-tool" onclick="toggleGapsOnly()" data-tooltip="学術論文が未接続の未研究・未対策脅威ノードのみを画面に絞り込みます" data-tooltip-pos="bottom"><span class="filter-dot" style="background-color: #8B5CF6;"></span>Gaps のみ (<span id="valGapsOnlyCount">0</span>)</button>
     ```
   - アクティブ時に `.active` クラスを付与し、ボタンテキストを `Gaps のみ (ON)` に切り替え。
   - Gaps 件数バッジ（`valGapsOnlyCount`）をデータフェッチ時に自動更新。

2. **状態管理とフィルタリングロジック (`site/dashboard.html`)**:
   - 状態変数 `let filterGapsOnly = false;` を追加。
   - `window.toggleGapsOnly()` 関数:
     - `filterGapsOnly = !filterGapsOnly;` をトグル。
     - ボタンの表示スタイル・クラスを更新。
     - `applyCtiFilter()` を再実行。
   - `applyCtiFilter()`:
     - `if (filterGapsOnly)` の場合:
       - `filteredNodes = filteredNodes.filter(n => !!n.is_research_gap);`
       - Gaps ノード集合の間で結ばれるエッジのみを `filteredEdges` に残す。
       - `graphQueryResultBadge` に「🚨 Research Gaps 抽出: ${filteredNodes.length} 件 (未対策・未研究ノード)」を表示。
     - `updateNodeRadii(NODES, EDGES)` を呼び出し、抽出された Gaps ノード群の頂点半径・表示を更新。
     - Gaps ノードには目立つ外枠破線やハイライトスタイル（`#EF4444` または `#F59E0B`）を維持。

3. **設計書更新 (`docs/designs/DSN-14-graph_engineering_dashboard.md`)**:
   - Section 11 に「11.12 未研究脅威（Research Gaps Only）フィルタ機能」を追記。

4. **自動テストの追加 (`tests/web/test_dashboard_graph_tab.py`)**:
   - `test_dashboard_research_gaps_only_filter`:
     - `id="btnFilterGapsOnly"` および `id="valGapsOnlyCount"` の存在確認。
     - `toggleGapsOnly` 関数および `filterGapsOnly` 状態変数の定義確認。
     - `applyCtiFilter` 内における `is_research_gap` フィルタリング処理の検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] ツールバーの CTI フィルタ領域に「🚨 Gaps のみ」ボタンが配置されていること。
- [x] ボタン押下で、未研究・未対策ノード（`is_research_gap === true`）のみが画面に即座に抽出表示されること。
- [x] 再度押下すると通常の全ノード表示（または現在のカテゴリフィルタ）に復帰すること。
- [x] 「⚡ Highlight Gaps」トグルや孤立ノード非表示トグルと競合せず整合して動作すること。
- [x] `tests/web/test_dashboard_graph_tab.py` の新規テストを含む全自動テストが 100% PASS すること。
- [x] 設計書 `DSN-14` に仕様が完全同期されていること。

