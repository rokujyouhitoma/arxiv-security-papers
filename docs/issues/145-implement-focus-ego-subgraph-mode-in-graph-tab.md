---
ID: 145
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] /dashboard tab=graph における特定ノードのフォーカス・エゴネットワーク抽出機能の実装 (ID: 145)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、任意のノードをダブルクリック（またはサイドインスペクターから「🎯 フォーカス」ボタンを押下）した際に、**その中心ノードから 1〜2 ホップ以内の直接関係ノード・エッジのみを強調表示し、無関係なノードを一時的にフェードアウト（半透明化または非表示）**にする「エゴネットワーク（Ego Subgraph）フォーカス機能」を実装する。
膨大なグラフの中から、特定の論文や攻撃手法の因果関係チェーンに完全に集中して探索できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 137: グラフクエリ・コンソール（`ego: <node> <depth>` サポート）
  - Issue 138: 専用 Graph タブの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/145-implement-focus-ego-subgraph-mode-in-graph-tab`

1. **操作インタラクションの拡張**:
   - ノードのダブルクリックイベント、およびサイドインスペクター Drawer (`nodeCallout`) 内に「🎯 このノードにフォーカス (Ego 2-Hop)」ボタンを追加。
2. **フォーカスレンダリングロジック**:
   - 状態変数 `let focusedNodeId = null;` および `let focusedHopNodeIds = new Set();` を管理。
   - ノードから BFS (幅優先探索) で 1〜2 ホップの隣接ノード ID 集合を算出。
   - キャンバス描画時に、対象外ノードのアルファ値（不透明度）を `0.08`（ほぼ透明）に減衰、または非表示化。
   - フォーカス対象ノード・エッジにパルスアニメーションまたは外枠グロー効果を付与。
   - キャンバスの空白部分をクリック、または「✕ フォーカス解除」ボタンで通常表示へ復帰。
3. **自動テストの追加**:
   - フォーカスボタンおよびダブルクリックハンドラーの登録を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ノード詳細 Drawer に「🎯 フォーカス」ボタンが配置されていること。
- [ ] ボタン押下またはダブルクリックで、1〜2ホップ以内の関連サブグラフのみがクローズアップ表示されること。
- [ ] 背景クリックまたは解除ボタンで通常モードに戻ること。
- [ ] 自動テスト・品質ゲートに合格すること。
