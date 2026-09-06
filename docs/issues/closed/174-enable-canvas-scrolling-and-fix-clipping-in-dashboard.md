---
ID: 174
種別: Bug
優先度: High
ステータス: Closed (Completed)
---

# [BUG] dashboard.html における Canvas 領域の見切れ解消、コントロールデッキ表示切替、およびスクロール（縦スクロール＆キャンバス内パン/ズーム）機能の実装 (ID: 174)

## 1. 概要 / Summary
`/dashboard.html`（または `/dashboard`）の Knowledge & CTI Graph 画面において、ブラウザのウィンドウサイズや画面の高さ（特にノート PC、低解像度ディスプレイ、または開発者ツール表示時）によって Canvas 領域や下部フッターが見切れてしまい、画面全体の縦スクロールができない現象が発生している。

さらに、上部コントロールデッキ（`graph-control-deck`: グラフモード切替、ノード種別フィルタ、確信度・推論ルールフィルタ、次数フィルタ、クエリコンソール等）が 2 段構成となっており画面縦幅の多くを占有しているため、解像度によっては Canvas の有効描画エリアが極端に圧迫される。現在、ヘッダーの折りたたみ（`toggleDashboardHeader` / `H` キー）は可能であるものの、コントロールデッキ自体の表示/非表示（格納/展開）を切り替える手段が存在しない。

また、Canvas 内に多数のノードが表示された際、外周に位置するノードがキャンバスの表示領域外に見切れる場合があるが、Canvas 内でのマウスホイールによるズーム操作（拡大/縮小）や背景ドラッグによる視点移動（パン）が実装されておらず、見切れたノードを画面内に引き戻すスクロール・探索ができない。

本 Issue では以下の 3 点を包括的に改修し、Canvas の見切れ解消と快適なスクロール・最大化操作を実現する：
1. **コントロールデッキの表示/非表示トグル（Toggle Graph Control Deck）の実装**:
   - `graph-control-deck` の格納・展開を切り替える関数 `window.toggleGraphControlDeck(forceState)` を新設。
   - ツールバーおよびキャンバスフローティングUIにトグルボタン（`btnToggleControlDeckQuick`, `btnFloatingDeckToggle`）、およびヘッダーユーティリティ（`deckToggleHeaderBtn`）を設置し、キーボードショートカット（`D` キー）にも対応。
   - コントロールデッキ格納時は Canvas を画面一杯まで最大化拡張（`resizeCanvas()` 連動）し、状態を `localStorage`（`dashboard_deck_hidden`）に永続化。
2. **ページ全体の縦スクロール（Page Vertical Scrolling）の有効化**:
   - `style.css` の `html, body { overflow: hidden; }` によるグローバルなスクロール阻害を `dashboard.html` 内で解除し、画面縦幅が縮小した場合でもページ全体を自然に縦スクロールできるようにする。
   - `.graph-workspace` の `min-height` や `height: calc(100vh - ...)` を見直し、コントロールデッキの折り返し発生時でもフッターまで確実にスクロール到達可能にする。
3. **キャンバス内のスクロール・ズーム＆パニング（Canvas Pan & Zoom Navigation）の実装**:
   - 操作ガイド（Issue 166 で定義された「ホイールスクロール: グラフのズームイン / ズームアウト」「ドラッグ: ノード移動またはグラフ全体のパン」）の仕様を完全に実装。
   - `wheel` イベントによる Canvas ズームイン/ズームアウト（0.25x 〜 4.0x）の実装。
   - 背景ドラッグによる Canvas 全体の視点移動（Pan: オフセット $x, y$ の追随）。
   - 座標変換（Screen Coord $\leftrightarrow$ World Coord）をノードクリック・ホバー判定（`findNodeAt`）および物理シミュレーション描画へ連動。

### 再現手順 / Steps to Reproduce
1. ブラウザで `/dashboard.html` を開き、ウィンドウの縦幅を 600px 程度にリサイズする、または開発者ツールを開く。
2. 上部ヘッダー、コントロールデッキ、Canvas が表示されるが、コントロールデッキが画面縦幅を圧迫し、Canvas 下部や Footer が見切れる。
3. コントロールデッキを一時的に非表示にして Canvas を広げるボタンや機能が存在しない。
4. マウスホイールを回してもページが縦スクロールせず、見切れたフッターや Canvas 下部を閲覧できない。
5. Canvas 上でマウスホイールを回してもグラフがズームせず、背景をドラッグしても視点移動（パン）しないため、画面端のノードへスクロールできない。

### 再現環境 / Environment
- OS / Env: Linux / Web Browser (Google Chrome, Firefox, Safari)
- File: `site/dashboard.html`, `site/style.css`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `site/dashboard.html`
  - コントロールデッキ（`.graph-control-deck`）の表示/非表示（`.deck-hidden`）CSS スタイル。
  - キャンバス上部フローティング展開ボタン（`.btn-floating-deck`）。
  - ヘッダーユーティリティボタン（`#deckToggleHeaderBtn`）の設置。
  - `toggleGraphControlDeck(forceState)` 関数の実装と `localStorage` 永続化、ショートカット `D` キー連動。
  - `html, body` の `overflow-y: auto;` 設定（グローバル `style.css` の `overflow: hidden` をオーバーライド）。
  - `.graph-workspace` のレイアウト調整（柔軟な最小高とスクロール対応）。
  - Canvas 2D コンテキストにおける Pan ($tx, ty$) および Zoom ($scale$) 状態管理。
  - `wheel` イベントリスナー（ズームイン/ズームアウト）。
  - `mousedown` / `mousemove` / `mouseup` における背景ドラッグ（パン移動）の処理。
  - `findNodeAt` におけるワールド座標変換（逆行列/オフトランスフォーム）の適用。
  - `render()` における `ctx.translate` および `ctx.scale` の適用とグリッド背景のワールド追随。
- [x] `site/style.css`
  - クラウドコンソール側とダッシュボード側で競合するレイアウト制約の点検。
- [x] `tests/web/test_dashboard_graph_tab.py`
  - コントロールデッキ表示切替トグル（関数・ボタン・クラス）、Canvas スクロール関連スタイル、およびズーム/パン用スクリプト・リスナーの存在検証テスト追加。
- [x] `tests/web/test_dashboard_html.py`
  - レイアウト回帰テスト。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **コントロールデッキの固定配置による作業領域圧迫**:
   - ヘッダー（48px）に加え、2 行のコントロールデッキ（約 80〜140px）が常時表示されており、画面解像度やウィンドウサイズが小さい場合に Canvas 表示領域の大半が奪われていた。ヘッダーの折りたたみ機構はあるものの、コントロールデッキを隠して Canvas 単体を最大化するスイッチが用意されていなかった。
2. **グローバルスタイルシート (`style.css`) の `overflow: hidden` 制約**:
   - `site/style.css` L86 において `html, body { overflow: hidden; }` が定義されている。
   - `dashboard.html` は `<link rel="stylesheet" href="style.css">` を読み込んでいるが、`body` 側の指定が `overflow-x: hidden;` に留まっており、`overflow-y` が暗黙に `hidden` のままとなっていたため、画面高が不足した際にブラウザのスクロールバーが表示されず、見切れた部分へ到達できなかった。
3. **操作ガイドと実装の乖離（未実装の Canvas ズーム・パン）**:
   - Issue 166 で整備された操作ガイドドロワーには「ホイールスクロール: グラフのズームイン / ズームアウト」「ドラッグ: ノード移動またはグラフ全体のパン」と明記されていたが、実コードには `wheel` リスナーが存在せず、ドラッグ処理もノード個別ドラッグしか考慮されていなかった。
   - グラフ描画ループ（`render`）も固定キャンバス解像度（$0 \dots \text{width}, 0 \dots \text{height}$）の直接描画となっており、ワールド座標変換機構（View Transform）が欠落していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 
  - ブラウザのズーム機能（`Ctrl + -` / `Cmd + -`）で全体を縮小表示する。または `H` キーを押してヘッダーを折りたたみ、作業領域を広げる。
* **恒久対策 (Permanent Fix)**: 
  1. `graph-control-deck` をワンクリックまたはショートカット（`D` キー）で折りたたみ・再展開できるトグル機能を実装し、Canvas 領域を即座に最大化できるようにする。
  2. `dashboard.html` 内のスタイルにて `html, body { overflow-x: hidden; overflow-y: auto; height: auto; min-height: 100vh; }` を適用し、画面縦幅が狭い場合でも確実にページスクロールを可能にする。
  3. Canvas 描画エンジンに Pan / Zoom 機構（`viewTransform = { x, y, scale }`）を組み込み、マウスホイールでのスムーズズームと背景ドラッグによるパニングを完全実装する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/174-enable-canvas-scrolling-and-fix-clipping-in-dashboard`

1. **コントロールデッキの表示切替トグル実装 (`site/dashboard.html`)**:
   - CSS: `.graph-control-deck.deck-hidden { display: none !important; }` を追加。
   - フローティング展開バー: デッキ非表示時に Canvas 上部に現れる半透明ピルボタン（`btnFloatingDeckToggle`: `🎛️ コントロールデッキ表示 (D)`）を設置。
   - ツールバー内格納ボタン: `btnToggleDeckQuick`（`▲ デッキ格納`）を追加。
   - JS: `window.toggleGraphControlDeck(forceState)` を実装し、LocalStorage（`dashboard_deck_hidden`）と `resizeCanvas()` を連動。
   - ショートカット: `D` キーでデッキ開閉を即座にトグル。
2. **CSS レイアウト修正 (`site/dashboard.html`)**:
   - `html, body` の `overflow-y: auto;` を明示し、ページ全体のスクロールを許可。
   - `.graph-workspace` の高さを調整し、画面が小さい場合にもコンテンツが破綻せずスクロール可能にする。
3. **Canvas ズーム＆パン機構の実装 (`site/dashboard.html`)**:
   - 状態変数 `viewTransform = { x: 0, y: 0, scale: 1.0 }` および `isPanning = false`, `panStart = { x: 0, y: 0 }` を追加。
   - 座標変換ヘルパー:
     - `screenToWorld(sx, sy)`: スクリーン座標からグラフ空間座標への変換。
     - `worldToScreen(wx, wy)`: グラフ空間座標からスクリーン座標への変換。
   - `wheel` イベントリスナー:
     - カーソル位置を中心としたスムーズズーム（`scale` を 0.3 から 3.0 の範囲でクランプ）。
   - `mousedown` / `mousemove` / `mouseup`:
     - ノード以外をクリックした場合は `isPanning = true` とし、マウス移動量に応じて `viewTransform.x`, `viewTransform.y` を更新。
     - カーソルを `grab` / `grabbing` に切り替え。
   - `render()`:
     - `ctx.save()` $\to$ `ctx.translate(viewTransform.x, viewTransform.y)` $\to$ `ctx.scale(viewTransform.scale, viewTransform.scale)` による描画。
     - 背景グリッドも視点移動に合わせて描画。
4. **テスト追加 & 検証**:
   - `tests/web/test_dashboard_graph_tab.py` にコントロールデッキ表示切替機能、スクロールスタイル、ズーム/パン機構の検証テストを追加。
   - `make verify_quality` を実行し、合格を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `btnToggleDeckQuick` ボタンのクリックまたは `D` キー押下で `graph-control-deck` がスムーズに折りたたまれ、Canvas がフルハイトに拡張されること
- [x] デッキ非表示時に Canvas 上部のフローティングボタン `btnFloatingDeckToggle` または `D` キーでいつでもコントロールデッキを再展開できること
- [x] ウィンドウ縦幅を縮小させた際、ブラウザの垂直スクロールバーが機能し、Canvas 下部および Footer までスクロール到達できること
- [x] Canvas 上でマウスホイールを操作した際、カーソル位置を中心としてグラフが滑らかにズームイン / ズームアウトできること
- [x] Canvas 背景をドラッグした際、グラフ全体が追従してパン（視点移動）できること
- [x] ズーム・パン状態でもノードのクリック判定、ダブルクリック（フォーカス）、ドラッグ移動が狂わず正確に動作すること
- [x] 操作ガイドドロワーの記載通りの操作感を提供できること
- [x] 既存の単体・結合テストスイートおよび品質ゲート（`make verify_quality`）が 100% PASS すること
