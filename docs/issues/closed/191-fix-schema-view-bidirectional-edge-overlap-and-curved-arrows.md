---
ID: 191
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] Schema View における逆関係・双方向エッジの重なり解消（二次ベジェ曲線・有向矢印・ラベル位置オフセット対応） (ID: 191)

## 1. 概要 / Summary

Web ダッシュボード（`/dashboard tab=graph`）の「📐 Schema View」（W3C OWL 2.0 TBox スキーマビュー）において、同一ノード対の間に存在する逆関係エッジ（例：`Paper` と `PublicationVenue` 間の `presentedAt`（採択・発表される）および `venuePresentedPaper`（採択・発表された論文））が幾何学的に同一の直線として重なって描画され、エッジが1本に見えてしまう問題が発生している。

また、ノードホバー時のエッジラベルも同一の中点座標に上書き描画されて文字が重なって判読不能となり、かつ有向矢印（Arrowhead）が存在しないため関係の向きが視覚的に識別できない。

本改修では、同一ノード対間の双方向・並行エッジを自動判定し、二次ベジェ曲線（`quadraticCurveTo`）による湾曲オフセット描画、有向矢印の付与、および制御点に基づいたエッジラベル配置オフセットを実装し、2本のエッジを分離して明瞭に視覚化する。

### 再現手順 / Steps to Reproduce
1. ブラウザで `/dashboard` または `dashboard.html` を開く。
2. グラフモードを「📐 Schema View」に切り替える。
3. `PublicationVenue`（採択会議・出版媒体）または `Paper`（学術論文）ノードを確認・ホバーする。
4. `Paper` ↔ `PublicationVenue` のエッジが1本に重なって表示され、ホバー時のラベル「採択・発表される」と「採択・発表された論文」が同一点に重なって潰れる。

### 再現環境 / Environment
- File: [site/dashboard.html](../../site/dashboard.html)
- Graph Mode: Schema View (`currentGraphMode === 'schema'`) および CTI Graph (`currentGraphMode === 'cti'`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/dashboard.html](../../site/dashboard.html) (Canvas エッジ描画ループ、双方向エッジ判定、二次ベジェ曲線描画、矢印描画、ラベルオフセット)
- [ ] [tests/web/test_dashboard_html.py](../../tests/web/test_dashboard_html.py) (ダッシュボード HTML/JS の回帰テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **直線描画の制限**: `EDGES.forEach` において、`ctx.moveTo(u.x, u.y); ctx.lineTo(v.x, v.y);` でエッジを直線描画しているため、$A \to B$ と $B \to A$ の線分座標が完全に一致し、2本のエッジが物理的に重なる。
2. **ラベル座標の単一固定**: ホバー時のラベル描画座標が線分の中点 `((u.x + v.x) / 2, (u.y + v.y) / 2)` にハードコードされているため、往路・復路のラベルが同一ピクセルに重なって描画される。
3. **有向矢印の欠如**: 線分のみを描画し矢印（Arrowhead）を描画していないため、エッジの始点と終点の方向性が判別できない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: サイドパネル（Inspector）の詳細リレーション一覧を参照して関係性を確認する。
* **恒久対策 (Permanent Fix)**:
  1. エッジ群から同一ペア `(min(u,v), max(u,v))` を持つエッジをグルーピングし、双方向・複数エッジに曲率オフセットインデックス（`curvature`）を付与。
  2. Canvas 描画で二次ベジェ曲線 `ctx.quadraticCurveTo(cx, cy, tipX, tipY)` を使用し、進行方向右側に湾曲させる。
  3. ターゲットノードの半径手前の位置に進行方向を示す有向矢印（Arrowhead）を描画する。
  4. ラベル位置をベジェ曲線の幾何学的曲率中点 $(lx, ly) = ((mx + cx) / 2, (my + cy) / 2)$ 付近に配置し、テキスト同士の重なりを解消する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/191-fix-schema-view-bidirectional-edge-overlap`

1. **エッジペアリングと曲率オフセット計算**:
   - `buildEdgePairIndex(edges)` 関数を追加し、無向キー `pairKey = u.id < v.id ? u.id + ':::' + v.id : v.id + ':::' + u.id` でエッジを分類。
   - ペア内のエッジ本数 $K$ が 2 以上の場合、各エッジに固有の `curvatureOffset`（例: 双方向なら進行方向右側へ $+24\text{px}$）を割り当てる。単一エッジは $0\text{px}$（直線）。
2. **二次ベジェ曲線および有向矢印の描画エンジン実装**:
   - 始点 $u$, 終点 $v$ からベクトル $(dx, dy)$、距離 $dist$、法線単位ベクトル $(nx, ny) = (-dy/dist, dx/dist)$ を算出。
   - 制御点 $(cx, cy) = (mx + nx \cdot offset, my + ny \cdot offset)$ を計算（$mx, my$ は中点）。
   - 終点 $v$ の半径 $r$ 手前の矢印先端座標 $(tipX, tipY)$ を接線ベクトルに基づいて決定。
   - `ctx.quadraticCurveTo(cx, cy, tipX, tipY)` で曲線をストローク描画。
   - 先端 $(tipX, tipY)$ に塗りつぶし三角形の有向矢印（長さ 8px, 幅 5px）を描画。
3. **エッジラベル座標の最適化**:
   - ホバー時のラベル描画座標を曲線の中点 $lx = (mx + cx)/2, ly = (my + cy)/2$ に設定。
   - 背景半透明バブルとテキストシャドウを適用し、エッジ線や他ノードとの視認性を確保。
4. **自動テスト・回帰検証**:
   - `tests/web/test_dashboard_html.py` にベジェ曲線・矢印描画・エッジペアインデックスのテストケースを追加。
   - `make build_js`, `make check_format`, `make static_analysis`, `make test` を実行し全品質ゲートをクリア。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `Paper` ↔ `PublicationVenue` 間で「採択・発表される」と「採択・発表された論文」が2本の独立した湾曲エッジとして分離表示されること。
- [x] 全有向エッジにおいて、終点ノードの手前に進行方向を示す有向矢印（Arrowhead）が正しく描画されること。
- [x] ホバー時に両エッジのラベルが各曲線の制御点付近にオフセット配置され、文字の重なりが完全に解消されること。
- [x] 単一方向エッジは直線として美しく描画され、不要な歪みが発生しないこと。
- [x] `tests/web/test_dashboard_html.py` のテストケースが通過すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で通過すること。
- [x] `make test` および `make build_js` が 100% PASS すること。
