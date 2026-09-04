---
ID: 146
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] /dashboard tab=graph におけるエッジ関係性（Relation Type）個別フィルタ機能の実装 (ID: 146)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、CTI ナレッジグラフのエッジ関係性（`EXPLOITS`, `MITIGATES`, `DISCLOSES`, `SUBCLASS_OF` 等）を個別にトグルで表示/非表示にできる「エッジ関係性フィルタ」を実装する。
「防御メカニズム（`MITIGATES`）の関係チェーンだけを追跡したい」「脆弱性の悪用関係（`EXPLOITS`）のみに絞り込みたい」といった具体的な分析目的に応じて、特定タイプのエッジおよびその接続サブグラフを抽出・比較できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 135: CTI ナレッジグラフデータ基盤およびインタラクティブ可視化の実装
  - Issue 138: 専用 Graph タブの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/146-implement-edge-relation-type-filter-in-graph-tab`

1. **凡例 / ツールバー連携 UI の拡張**:
   - `ctiLegend`（または `mesh-toolbar`）内の各関係性（`EXPLOITS`, `MITIGATES`, `DISCLOSES`, `SUBCLASS_OF`）をクリック可能なトグルチップ化。
   - チップをクリックすると、そのエッジ種別の表示（有効/無効）が切り替わる。
2. **エッジフィルタリングロジック**:
   - 状態オブジェクト `let activeEdgeRelations = { EXPLOITS: true, MITIGATES: true, DISCLOSES: true, SUBCLASS_OF: true };` を管理。
   - `EDGES` 構築時およびレンダリング時に、`activeEdgeRelations[e.rel] !== false` のエッジのみを描画・物理計算に組み込む。
3. **自動テストの追加**:
   - 関係性トグル要素およびエッジ除外ロジックの存在・動作確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 凡例またはツールバーに各エッジ種別（EXPLOITS, MITIGATES, DISCLOSES, SUBCLASS_OF）のトグルチップが配置されていること。
- [ ] 特定の関係性をオフにすると、該当するエッジが即座に非表示になること。
- [ ] 全テスト・品質ゲートに合格すること。
