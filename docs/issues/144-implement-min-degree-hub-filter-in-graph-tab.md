---
ID: 144
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] /dashboard tab=graph における最小次数フィルタ（Min-Degree / Hub Filter）の実装 (ID: 144)

## 1. 概要 / Summary
`http://localhost:8000/dashboard.html?tab=graph` において、頂点のエッジ接続数（次数 $k$）に応じた段階的な最小次数フィルタ（例: `Min Degree: All / ≥1 / ≥2 / ≥3`）を実装する。
エッジ数が少ない末端のリーフノードを段階的に非表示にし、重要論文や中核となる攻撃手法・共通脆弱性（CWE）などの**ハブノード（コアネットワーク骨格）**を瞬時に抽出・分析できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: `docs/designs/DSN-14-graph_engineering_dashboard.md` (Section 11: Dedicated Graph Workspace)
- 関連Issue:
  - Issue 140: ノード半径の面積比例スケーリング（$R \propto \sqrt{1+k}$）
  - Issue 143: 孤立ノード（EdgeなしVertex）非表示トグル機能

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html)
- [ ] [tests/web/test_dashboard_graph_tab.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_graph_tab.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/144-implement-min-degree-hub-filter-in-graph-tab`

1. **UI コントロール追加 (`site/dashboard.html`)**:
   - `mesh-toolbar` 内に「次数フィルタ: [All | ≥1 | ≥2 | ≥3]」ボタングループまたはドロップダウンを配置。
2. **次数フィルタリングロジック**:
   - 状態変数 `let minDegreeThreshold = 0;` を保持。
   - `applyCtiFilter()` およびグラフ構築時に `degreeMap` を算出し、`node.degree >= minDegreeThreshold` を満たすノードのみを `NODES` に追加。
   - フィルタされたノードに接続するエッジのみを `EDGES` に残す。
3. **自動テストの追加**:
   - 次数フィルタ UI 要素の存在確認および、閾値変更時のノード除外ロジックをテスト。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ツールバーに最小次数セレクター（All / ≥1 / ≥2 / ≥3）が配置されていること。
- [ ] 選択した閾値未満のノードと孤立したエッジが即座に非表示になること。
- [ ] All に戻すと全ノードが再描画されること。
- [ ] 自動テスト・品質ゲートに合格すること。
