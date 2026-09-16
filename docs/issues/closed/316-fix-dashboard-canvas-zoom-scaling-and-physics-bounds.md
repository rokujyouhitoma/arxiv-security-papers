---
ID: 316
種別: Bug / UX
優先度: High
ステータス: Closed
---

# [BUG/UX] ダッシュボード Canvas における縮小表示（ズームアウト）時の描画領域スケーリング不全および物理境界クランプの解消 (ID: 316)

## 1. 概要 / Summary
`site/dashboard.html` のナレッジグラフ表示画面において、グラフが表示された後に縮小表示（ズームアウト）やウィンドウ/コントロールデッキのリサイズを行った際、以下の 3 つの構造的不具合により Canvas の描画領域が正しくスケール・拡大利用されない問題が発生していた。

### 根本原因の構造的分析
1. **物理エンジン（`stepPhysics`）におけるスクリーン解像度のハードクランプ**:
   - `render()` ではワールド座標変換（`ctx.translate`, `ctx.scale`）を行っているにもかかわらず、毎フレームの `stepPhysics()` 内でノード座標 `(n.x, n.y)` を固定スクリーン解像度 `[24, width - 24]` × `[padY, height - padY]` に強制拘束していた。
   - その結果、ズームアウト（`scale < 1.0`）してもノード群が画面中央の狭い矩形領域に押し込められたままとなり、背後に広がった広大な Canvas ワールド空間へノードが分散・スケールしない。
2. **`resizeCanvas()` による固定インラインピクセル付与と CSS Flexbox 競合**:
   - `resizeCanvas()` で `canvas.style.width = width + 'px'` および `height = height + 'px'` を直接上書きしていたため、CSS の `width: 100%; height: 100%` が無効化され、親コンテナ（`.canvas-container`）が縮小された際に Canvas 要素が縮小をブロックし、レイアウト再計算が破綻・停止していた。
3. **キャンバスリサイズ時の既存ノード比例スケーリング欠落**:
   - 初期化時（`n.x === 0 && n.y === 0`）以外はキャンバス解像度変更に伴う座標変換が行われず、縮小時に端のノードが境界壁に衝突・圧迫されて密集し、再拡大時にも復元しなかった。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: W3C HTML Canvas 2D Context Level 2, W3C CSS Flexible Box Layout Module Level 1
- 関連 Issue: [#250](closed/250-implement-louvain-community-detection-for-cti-graph.md), [#253](closed/253-fix-context-mesh-paper-cluster-classification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `site/dashboard.html`:
  - `stepPhysics()`: ズーム倍率連動動的ワールド空間境界（Frustum Bounding Box）およびソフト中心引力（Softened Center Gravity）の適用
  - `resizeCanvas()`: インライン固定ピクセル付与の撤廃（CSS 100% 準拠）および既存ノードのキャンバス寸法比率スケーリング
  - ズーム・パン機構: 視点中央点追従およびスケールバッジ同期
- [x] `docs/issues/README.md`: Issue 台帳のステータス更新 (`Open (In Progress)`)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/316-fix-dashboard-canvas-zoom-scaling-and-physics-bounds`

### Step 1: `resizeCanvas()` の改善
- `canvas.style.width / height` への固定ピクセル書き込みを廃止し、親要素の CSS `width: 100%; height: 100%;` にレイアウトを完全委託。
- 前回のキャンバス解像度 `prevCanvasWidth`, `prevCanvasHeight` を保持し、寸法変化時に `scaleX = width / prevCanvasWidth`, `scaleY = height / prevCanvasHeight` を用いて既存ノードをキャンバス中心 `(width / 2, height / 2)` 基準で比例スケーリング。

### Step 2: `stepPhysics()` の動的ワールド空間スケーリング
- 現在のズーム倍率 `curScale = Math.max(0.1, viewTransform.scale)` を取得。
- ワールド空間の有効スパンを `worldSpanX = width / Math.min(1.0, curScale)`, `worldSpanY = height / Math.min(1.0, curScale)` として計算。
- 中心引力を `effectiveKCenter = K_CENTER * Math.min(1.0, curScale)` に緩和し、ズームアウト時にノード同士の反発力（`K_REPULSION`）が自然に働いてワールド空間全体へ美しく拡散するように調整。
- 境界クランプを `[cx - halfSpanX, cx + halfSpanX]` × `[cy - halfSpanY, cy + halfSpanY]` に動的拡張。

### Step 3: ゼロ除算・オーバーフロー耐性（安全対策）
- `curScale` や `prevCanvasWidth` のゼロ除算チェック、`Math.max` によるガード処理を徹底。

---

## 5. 脅威分析およびセキュリティ要件 / Threat Modeling & Security
- **入力サニタイズ**: 今回の変更は数値演算および Canvas 描画座標系の変換に限定されており、ユーザー入力文字列の DOM 挿入は伴わない（既存の `escapeHtml` 適用済み）。
- **ReDoS / 物理発散防止**: ズーム倍率の下限を `0.1` でガードし、`worldSpan` の極端な発散や `NaN` 伝播を防止。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] ズームアウト（グラフ縮小）操作時に、ノード群が中央の狭い矩形領域に閉じ込められず、Canvas 描画領域全体へクーロン反発力で自然にスケール・拡散すること。
- [x] ウィンドウやコントロールデッキの縮小時に Canvas が Flexbox コンテナに合わせて即座に縮小追従し、描画バッファ解像度（DPR 対応）が自動再計算されること。
- [x] キャンバスリサイズ時に既存ノード群の中心相対配置が比例維持されること。
- [x] JavaScript 構文チェック（`node --check`）およびプロジェクト全品質ゲート（`make py_compile`, `make static_analysis`, `make test`）が 100% PASS すること。
