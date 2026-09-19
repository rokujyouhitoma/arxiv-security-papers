---
ID: 348
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR] GraphCanvasEngine: site/dashboard.html からの力学モデル・Canvas 描画の完全分離 (ID: 348)

## 1. 概要 / Summary

現在 `site/dashboard.html` の `<script>` タグ内に約 2,900 行にわたってベタ書きされている力学シミュレーション（クーロン反発力、フック引力、減衰、境界反発）、Canvas 2D レンダリングパイプライン（ノード・エッジ・ハロー・矢印・ラベル）、マウス/タッチ操作（パン、ズーム、ドラッグ、ホバー判定）を、独立したモジュール `GraphCanvasEngine` として `site/js/frameworks/graph-canvas.js` に完全抽出し分離する。

`dashboard.html` のインラインスクリプトを最小化（DOM 宣言と初期化のみ）し、`HSM`（操作状態管理）、`DisjointSet`（連結成分抽出）、`Publisher`（ノード選択イベント）、`TimingUtils`（`requestAnimationFrame` ループ制御）と緊密に連携させることで、保守性とレンダリング性能を劇的に向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.5, 8)
  - [DSN-14: 論文・脅威ナレッジグラフ & エンジニアリングダッシュボード設計書](../designs/DSN-14-graph_engineering_dashboard.md)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/graph-canvas.js`](../../site/js/frameworks/graph-canvas.js) (新規)
- [ ] [`site/dashboard.html`](../../site/dashboard.html) (インラインスクリプト大幅削減)
- [ ] [`site/externs.js`](../../site/externs.js) (`GraphCanvasEngineInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/348-extract-graph-canvas-engine-from-dashboard`

1. **`GraphCanvasEngine` クラスの設計と実装**:
   - `constructor(canvasElement, options = {})`
   - サブシステム分割:
     - `PhysicsSimulator`: クーロン反発・バネ力・速度ベリレ積分・シミュレーション安定判定
     - `CanvasRenderer`: 空間変換マトリクス（ズーム・オフセット）、LOD（Level of Detail）に応じたラベル描画制御
     - `InteractionHandler`: マウスホイール、ドラッグ、マルチタッチピンチズーム、近傍探索（Spatial Index）
   - メソッド: `loadData(graphData)`, `startSimulation()`, `stopSimulation()`, `zoomIn()`, `zoomOut()`, `resetView()`, `filterLCC()`, `highlightNode(nodeId)`
2. **Closure Compiler 適合**:
   - `site/externs.js` に `GraphCanvasEngine` の型定義を追加
3. **`site/dashboard.html` の軽量化**:
   - `new GraphCanvasEngine(canvas)` を呼び出すだけの極小エントリポイントへ移行

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/graph-canvas.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/dashboard.html` のスクリプト行数が 2,900 行から 200 行未満にスリム化されること
- [ ] 従来のパン・ズーム・ドラッグ・クラスタハイライト機能が 100% 損なわれず動作すること
- [ ] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
