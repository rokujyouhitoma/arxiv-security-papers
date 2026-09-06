---
ID: 181
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/UIUX] graph.html (dashboard.html) におけるグローバルヘッダー・コントロールデッキ表示時の Canvas 縦縮み歪みおよびノード選択判定不具合の解消 (ID: 181)

## 1. 概要 / Summary
`dashboard.html`（Knowledge & CTI Graph画面）において、グローバルヘッダー（`#dashboardHeader`）およびコントロールデッキ（`.graph-control-deck`）を表示している際に、Canvas上の描画要素（頂点ノード・エッジ・テキスト）が縦方向に不自然に縮んで（扁平な楕円形に潰れて）表示され、その結果ノードをクリック・ホバーした際のヒット判定（選択処理）に縦方向のズレが生じて選択しづらくなる重大な表示・操作性バグが発生している。

本問題は、UI/UX & Documentation Designer エージェントが主導し、システムの視覚的完全性（アスペクト比 1:1 の真円描画）およびインタラクション精度（マウス座標とCanvasワールド座標の完全一致）を恒久的に保証する改修を行う。

### 再現手順 / Steps to Reproduce
1. ブラウザで `/dashboard.html`（または `/dashboard`）を開く。
2. グローバルヘッダー（`#dashboardHeader`）およびコントロールデッキ（`.graph-control-deck`）が両方表示されている状態にする（デフォルトまたはショートカット `H`, `D` で展開）。
3. グラフ上の頂点ノードの形状を観察すると、真円であるべきノードが縦に潰れた扁平な楕円形（アスペクト比の歪み）としてレンダリングされる。
4. ノードにマウスカーソルを合わせる、またはクリックしてインスペクターを開こうとすると、見た目の位置と内部ヒット判定座標に縦方向のオフセット（ズレ）が生じ、ノードが正しく選択できない／選択しにくい。
5. ヘッダーやデッキを折りたたむ（ショートカット `H` / `D`）、または CTI フィルターの折り返し等でデッキ高さが変動した際に、歪み率がさらに悪化または不整合を起こす。

### 再現環境 / Environment
- OS / Env: Linux / Web Browser (Chrome, Firefox, Safari, Edge)
- File: `site/dashboard.html`
- Component: Force-Directed Graph 2D Canvas Engine (`#graphCanvas`), Layout Flexbox Container (`.graph-workspace`, `.canvas-container`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [site/dashboard.html](file:///workspace/arxiv-security-papers/site/dashboard.html) (Canvas CSS, ResizeObserver 実装, 座標変換 `screenToWorld`, リサイズトリガー改善, ヒットテスト拡大)
- [x] [tests/web/test_dashboard_canvas_aspect_ratio.py](file:///workspace/arxiv-security-papers/tests/web/test_dashboard_canvas_aspect_ratio.py) (新規: Canvas寸法・ResizeObserver・ヒットテスト正規化の検証テスト)
- [x] [docs/designs/DSN-21-enterprise_design_system_and_cloud_console_uiux_architecture.md](file:///workspace/arxiv-security-papers/docs/designs/DSN-21-enterprise_design_system_and_cloud_console_uiux_architecture.md) (Canvas レスポンシブアスペクト比・レイアウト仕様の反映)
- [x] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md) (Issue 台帳登録)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
UI/UX およびシステムアーキテクチャの多角的観点からコードとレンダリング挙動を精査した結果、以下の4つの根本原因が複合して本不具合を誘発していることが判明した。

1. **CSS トランジションと不適切な固定ディレイ（`setTimeout(resizeCanvas, 40)`）によるビットマップ解像度と表示サイズの乖離**:
   - `header.console-header` には `transition: all 0.2s cubic-bezier(...)`（200ms）のトランジションが設定されている。
   - 一方、ヘッダーおよびコントロールデッキの開閉関数（`toggleDashboardHeader`, `toggleGraphControlDeck`）では、わずか 40ms 後（アニメーション進行度約20%の過渡状態）に `resizeCanvas()` が一度だけ実行されている。
   - アニメーション完了時点（200ms後）では `resizeCanvas()` が呼ばれないため、Canvas の内部ビットマップサイズ（`canvas.width`, `canvas.height`）が中間状態の解像度のまま固定される。
   - CSS 側で `#graphCanvas { width: 100%; height: 100%; }` が指定されているため、ブラウザの GPU コンポジタが親コンテナの最終サイズに合わせてビットマップを縦方向に伸縮（ストレッチ／スクイーズ）処理し、円が楕円に歪む。

2. **ResizeObserver の欠落とコントロールデッキ可変高への非追従**:
   - コントロールデッキ（`.graph-control-deck`）は、CTI フィルター展開時や画面幅に応じた折り返し（`flex-wrap: wrap`）により高さが動的に変動（約120px〜220px）する。
   - しかし、`dashboard.html` 内には `ResizeObserver` が存在せず、`window.resize` イベントと不完全なタイマーのみに依存していた。親コンテナ（`.canvas-container`）の高さ変化に Canvas ビットマップ解像度がリアルタイム追従できていなかった。

3. **CSS レイヤースタイルにおける `height: 480px` と Flexbox の競合**:
   - `dashboard.html` 158行目に `.canvas-container { height: 480px; }` の静的高さ指定が残存しており、1140行目の `.graph-workspace .canvas-container { flex: 1; min-height: 0; }` と競合していた。デッキ展開時に Flexbox の伸縮計算が中途半端になり、縦方向の潰れ感を増幅させていた。

4. **マウスイベント座標（`screenToWorld`）におけるビットマップ／CSS表示比率の未補正**:
   - `mousemove` および `mousedown` では `rect = canvas.getBoundingClientRect()` から `e.clientX - rect.left` を直接利用していた。
   - CSS 上でキャンバスが伸縮されている場合、表示上の 1px と Canvas 内部の 1px（DPR 考慮後）のスケール比率が不一致となり、クリックした位置と頂点ノードの判定位置に大きな縦ズレが発生して選択困難となっていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  - ヘッダー（Hキー）またはコントロールデッキ（Dキー）を格納して全画面表示にすることで歪みを一時的に軽減する。
* **恒久対策 (Permanent Fix)**: 
  1. **`ResizeObserver` の導入**: `.canvas-container` に `ResizeObserver` を接続し、CSS トランジション中および完了後、フォントロード、デッキ折り返し等、いかなるサイズ変動時にも正確に `canvas.width` / `canvas.height` を CSS ピクセル × DPR に 1:1 完全同期させる。
  2. **`canvas.style.width` / `canvas.style.height` の明示的同期**: ビットマップと CSS 表示サイズの乖離をゼロにし、GPU コンポジタによる不均等伸縮を完全排除する。
  3. **ヒットテスト座標のスケール補正**: `canvas.getBoundingClientRect()` と Canvas 内部論理寸法の比率（`scaleX`, `scaleY`）を `mousemove` / `mousedown` / `dblclick` / `wheel` で補正し、常に画面上の見た目と 100% 同一の位置でノード選択・ドラッグを可能にする。
  4. **ヒット判定半径のエビデンス拡張**: `findNodeAt` の判定半径を `Math.max(nodeRadius + 8, 16)` に設定し、UIUX ガイドライン（DSN-21）に準拠したエルゴノミクス（押しやすさ）を確保する。
  5. **CSS スタイルのクリーンアップ**: `.canvas-container` の不要な固定 `height: 480px` を解消し、Flexbox ワークスペース下で常に安定した `height: 100%` / `flex: 1` 振る舞いを徹底する。
  6. **Force-Directed 物理シミュレーションの Y 軸クランプ最適化**: 極端な横長アスペクト比でもノードが縦に押し潰されないよう、物理演算の境界パディング（`padX`, `padY`）を動的適応させる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/181-fix-canvas-vertical-distortion-and-hit-testing-in-graph-view`

1. **`site/dashboard.html` の Canvas リサイズエンジン刷新**:
   - `new ResizeObserver(() => resizeCanvas()).observe(canvas.parentElement)` を実装。
   - `resizeCanvas()` 内で `canvas.style.width = width + 'px'` および `canvas.style.height = height + 'px'` を明示設定。
   - `header` / `deck` トランジション完了イベント（`transitionend`）のハンドラを追加し、アニメーション終了時の完全な再調整を保証。

2. **マウス操作座標変換の堅牢化**:
   - `getBoundingClientRect()` の幅・高さと `width`・`height` の比率を計算し、`mx`, `my` を正規化。
   - `findNodeAt` のヒット判定領域を `Math.max(nodeRadius + 8, 16)` へ拡張し、高密度時でも意図したノードが確実に選択できる判定ロジックを実装。

3. **CSS レイアウト定義の修正**:
   - `.canvas-container` の静的 `height: 480px` を排除し、`.graph-workspace .canvas-container` に `height: 100%; flex: 1;` を明示。
   - コントロールデッキ表示時でも視認性に優れたキャンバス高さを確保。

4. **テストスイートの実装と検証**:
   - `tests/web/test_dashboard_canvas_aspect_ratio.py` を作成し、ResizeObserver 接続、スタイル設定、正規化計算、クリーンアップされた CSS を包括的に自動検証。
   - `make check_format` および `make static_analysis` を完全パス。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] グローバルヘッダーおよびコントロールデッキが表示されている状態で、ノードが真円（歪み率 1.0）でレンダリングされること。
- [x] ヘッダー・コントロールデッキの開閉（Hキー、Dキー、ボタン押下）を行っても、アニメーション中およびアニメーション後に Canvas のアスペクト比が歪まないこと。
- [x] ノードをクリックした際、カーソル位置にあるノードが 100% 確実に選択され、詳細インスペクター（Callout）が表示されること。
- [x] ノードのドラッグ操作およびホイールズームがカーソル位置と完全に同期してスムーズに動作すること。
- [x] `tests/web/test_dashboard_canvas_aspect_ratio.py` を含む全テストが PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー 0 件で PASS すること。
