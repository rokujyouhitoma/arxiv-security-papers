---
ID: 147
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT] /dashboard tab=graph における最大連結成分（LCC: Largest Connected Component）抽出機能の実装 (ID: 147)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、グラフ内の最大連結成分（Largest Connected Component: 最もノード数が多く相互接続されている主要クラスタ）のみを抽出し、2〜3ノードだけで孤立している周辺の「離れ小島クラスタ」を一括非表示にする「LCC 抽出トグル機能」を実装する。
マクロな全体ネットワークのコア構造をクリアに俯瞰できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 143: 孤立ノード（EdgeなしVertex）非表示トグル機能

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/147-implement-largest-connected-component-filter-in-graph-tab`

1. **グラフ連結成分解析アルゴリズム**:
   - Union-Find（Disjoint Set）または BFS による連結成分クラスタリングをクライアント側 JavaScript で実行。
   - ノード数が最大の連結成分（LCC）のノード ID 集合を特定。
2. **UI コントロール追加**:
   - ツールバーに「🌐 メイン成分のみ (LCC Only)」トグルボタンを追加。
   - ON にすると、LCC 以外の小規模クラスタを非表示化。
3. **自動テストの追加**:
   - LCC 解析ロジックおよびトグルボタンの動作を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ツールバーに「🌐 メイン成分のみ (LCC)」ボタンが配置されていること。
- [ ] ボタン押下で、最大連結成分以外の小規模クラスタが非表示になり、メインネットワークのみが残ること。
- [ ] 全テスト・品質ゲートに合格すること。
