---
ID: 318
種別: Feature / UX
優先度: High
ステータス: Closed
---

# [FEATURE/UX] ダッシュボード ナレッジグラフにおけるエッジ選択・関係性メタデータ＆エビデンス詳細インスペクターの実装 (ID: 318)

## 1. 概要 / Summary
`site/dashboard.html` のナレッジグラフ表示画面において、ノード（頂点）だけでなくエッジ（辺 / リレーション）も直接クリックして選択可能にし、エッジが保持するリレーション種別、確信度スコア/ティア、推論メカニズム、適用推論ルール、および原典論文からのエビデンス引用文（`evidence_quote`）を詳細インスペクターに表示する機能を実装する。また、関連仕様書 `docs/designs/DSN-14-graph_engineering_dashboard.md` を改定する。

### 解決する課題
- ナレッジグラフにおける本質的価値は、エンティティ（ノード）間の「因果関係・攻撃成立関係・防御実証関係（エッジ）」にある。
- 従来はエッジに格納された豊富な推論メタデータやエビデンス引用文を確認する手段がなく、せっかくのデータが潜在化していた。
- エッジを選択可能にすることで、セキュリティアナリストが「この攻撃成立の根拠はどの論文のどの記述か？」を即座に検証可能とする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-14 (Graph Engineering Dashboard)](../designs/DSN-14-graph_engineering_dashboard.md)
- 関連 Issue: [#317](closed/317-implement-node-hiding-and-unhiding-in-dashboard.md), [#316](closed/316-fix-dashboard-canvas-zoom-scaling-and-physics-bounds.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `site/dashboard.html`:
  - 当たり判定: `findEdgeAt(mx, my)` (直線・二次ベジェ曲線に対する最短距離計算、ノード優先)
  - 状態管理: `selectedEdge`, `hoveredEdge`, `selectEdge(edge)`, `closeEdgeCallout()`
  - 描画エンジン: `render()` 内のエッジ選択強調（太線 3.5px、アンバー強調、両端ノード連動ハイライト）
  - UI インスペクター: `#nodeCallout` のエッジ詳細表示（リレーション、確信度、ルール、エビデンス引用）
  - マウス・キーボード制御: クリックによるエッジ選択、背景クリック / `Esc` による解除
- [x] `docs/designs/DSN-14-graph_engineering_dashboard.md`: 第5章のインタラクションおよびインスペクター仕様の改定
- [x] `tests/web/test_dashboard_graph_tab.py`: 新規検証テストの追加
- [x] `docs/issues/README.md`: Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/318-implement-edge-selection-and-inspection-in-dashboard`

1. **`findEdgeAt(mx, my)` の実装**:
   - ワールド座標系において、マウスポインタと各エッジ（直線または二次ベジェ曲線）との最短距離 $d$ を算出。
   - $d \le 8\text{px}$ を満たす最も手前のエッジを検出。ノードとの重なり時はノードを優先。
2. **`selectEdge(edge)` とインスペクター表示**:
   - `selectedEdge = edge; selectedNode = null;`
   - コールアウトパネル（`#nodeCallout`）に、エッジのリレーションバッジ、確信度、推論ルール、および原典引用文（`evidence_quote`）を描画。
3. **エッジ描画（`render()`）の更新**:
   - `selectedEdge === e` の場合、`ctx.strokeStyle = '#d97706'`、`ctx.lineWidth = 3.5` で強調。両端ノード `u, v` もハイライト。
4. **DSN-14 の改定**:
   - 5.3 節に「ノード・エッジ二層ヒットテスト仕様」、5.4 節に「エッジ詳細インスペクター仕様」を明記。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] Canvas 上のエッジをクリックして選択できること（直線および曲線エッジに対応）。
- [x] 選択されたエッジおよび両端ノードが視覚的に強調描画されること。
- [x] コールアウトパネルにリレーション名、確信度、推論メカニズム、エビデンス引用文が表示されること。
- [x] 背景クリックまたは `Esc` でエッジ選択が解除されること。
- [x] DSN-14 設計書が改定され、エッジ選択仕様が体系的にドキュメント化されていること。
- [x] ユニットテスト全件 PASS、品質ゲートが 100% PASS すること。
