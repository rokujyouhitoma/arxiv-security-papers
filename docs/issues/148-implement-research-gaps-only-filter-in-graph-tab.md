---
ID: 148
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] /dashboard tab=graph における未研究・未対策脅威（Research Gaps Only）専用絞り込みフィルタの実装 (ID: 148)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、現在の「⚡ Highlight Gaps（オレンジ枠ハイライト）」トグルに加え、**学術論文による防御・分析がまだ存在しない攻撃手法や脆弱性（Research Gap ノード）のみを画面内にワンクリックで絞り込む「🚨 Gaps Only フィルタ」**を実装する。
未解決のセキュリティ脅威や、今後研究が求められる領域（ブルーオーシャン）を即座に一覧・抽出できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 135: CTI ナレッジグラフと Research Gaps 解析
  - Issue 137: `gaps` プリセットクエリ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/148-implement-research-gaps-only-filter-in-graph-tab`

1. **フィルターバー UI の拡張**:
   - `ctiFilters` 領域の「⚡ Highlight Gaps」ボタンの隣に「🚨 Gaps のみ (Gaps Only)」ボタンを追加。
2. **Gaps 絞り込みロジック**:
   - 状態変数 `let filterGapsOnly = false;` を追加。
   - `applyCtiFilter()` において、`filterGapsOnly === true` の場合は `n.is_research_gap === true` を満たすノード、およびそれらの直接接続関係のみを抽出して描画。
3. **自動テストの追加**:
   - Gaps Only フィルタボタンの存在および Gaps ノード絞り込み動作のテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ツールバーに「🚨 Gaps のみ」ボタンが配置されていること。
- [ ] ボタン押下で、未研究・未対策ノード（is_research_gap）のみが画面に抽出されること。
- [ ] 全テスト・品質ゲートに合格すること。
