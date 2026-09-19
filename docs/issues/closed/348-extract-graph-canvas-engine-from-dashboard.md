---
ID: 348
種別: Refactor
優先度: High
ステータス: Closed
---

# [REFACTOR] GraphCanvasEngine: site/dashboard.html からの力学モデル・Canvas 描画の完全分離 (ID: 348)

## 1. 概要 / Summary

現在 `site/dashboard.html` に組み込まれている力学シミュレーション（クーロン反発力、フック引力、中心引力、減衰、境界反発）、Canvas 2D レンダリングパイプライン（ノード・エッジ・ハロー・矢印・ラベル）、マウス/タッチ操作（パン、ズーム、ドラッグ、ホバー判定、座標正規化）を、独立したモジュール `GraphCanvasEngine` として `site/js/frameworks/graph-canvas.js` に完全抽出し分離・統合する。

`site/dashboard.html` の Canvas 制御ロジックを `GraphCanvasEngine` へ委託可能に構造化し、`HSM`（操作状態管理: `Normal.Idle`, `Normal.Panning`, `Normal.DraggingNode`, `Inspecting`）、`DisjointSet`（最大連結成分 LCC 抽出）、`Publisher`（ノード選択・ズームイベント通知）、`TimingUtils`（アニメーション・シミュレーションループ制御）と緊密に連携させることで、保守性とレンダリング性能を劇的に向上させる。また、既存の 52 件のダッシュボード回帰テスト（DOM 属性、関数シグネチャ、CSS セレクタ）との完全な後方互換性を保証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.5, 8)
  - [DSN-14: 論文・脅威ナレッジグラフ & エンジニアリングダッシュボード設計書](../designs/DSN-14-graph_engineering_dashboard.md)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)
  - [Issue 343: HSM (HierarchicalStateMachine) の JS 移植と状態管理統合](closed/343-port-hsm-core-to-frontend-state-governance.md)
  - [Issue 344: DisjointSet の JS 移植と LCC 計算](closed/344-port-disjoint-set-to-frontend-lcc-clustering.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/frameworks/graph-canvas.js`](../../site/js/frameworks/graph-canvas.js) (新規実装: 力学モデル・描画・操作エンジン)
- [x] [`site/dashboard.html`](../../site/dashboard.html) (`GraphCanvasEngine` との統合およびインターフェース互換維持)
- [x] [`site/externs.js`](../../site/externs.js) (`GraphCanvasEngineInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (エンジン単体テスト追加)
- [x] [`docs/issues/README.md`](README.md) (台帳更新)

---

## 4. セキュリティ考慮事項 / Security Analysis & Threat Modeling

1. **DOM XSS / Label Injection 防御**:
   - ノードラベルおよびツールチップ描画において、Canvas 2D API (`ctx.fillText`) はプレーンテキストのみを描画するため HTML タグは評価されないが、ノードプロパティのサニタイズ（制御文字の除去、最大文字数クランプ）を実施する。
2. **CPU / イベントループ枯渇 (DoS) の防止**:
   - 力学シミュレーションにおいて、ノード数が極大（$N > 1000$）の場合の $O(N^2)$ 計算暴走を防止するため、最大反復ステップ数およびシミュレーション停止閾値（運動エネルギー $\epsilon < 0.01$）を導入し、一定時間経過後に自動停止（Sleep）する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/348-extract-graph-canvas-engine-from-dashboard`

1. **`GraphCanvasEngine` クラスの設計と実装 (`site/js/frameworks/graph-canvas.js`)**:
   - コンストラクタ: `constructor(canvasElement, options = {})`
   - サブコンポーネント:
     - 空間変換: `screenToWorld(sx, sy)`, `worldToScreen(wx, wy)`, `getNormalizedCanvasMouse(e)`
     - 力学演算: `stepPhysics(dt)`（クーロン反発力、フックバネ力、中心重力、動的ワールド境界バウンディング、速度ベリレ積分）
     - レンダリング: `render()`（エッジ・矢印・曲率、ノード円・ハロー・バッジ、LOD ラベル描画、フォーカス/ホバーハイライト）
     - 操作状態マシン (`HSM` 統合): `Normal.Idle` $\leftrightarrow$ `Normal.Panning` $\leftrightarrow$ `Normal.DraggingNode` $\leftrightarrow$ `Inspecting`
     - LCC 抽出 (`DisjointSet` 統合): `computeLargestConnectedComponent(nodes, edges)`
     - イベント連携 (`Publisher`): `graph:node_selected`, `graph:viewport_change`, `graph:sim_stabilized`
   - パブリック API:
     - `loadData(graphData)`
     - `start()`, `stop()`, `render()`
     - `zoomIn(factor)`, `zoomOut(factor)`, `resetView()`, `fitToView()`
     - `filterLcc()`, `filterMinDegree(threshold)`, `hideIsolatedNodes(enable)`
     - `highlightNode(nodeId)`, `clearHighlight()`
     - `resize(width, height)`
     - `destroy()`
2. **`site/externs.js` 型定義追加**:
   - `GraphCanvasEngineInterface` を定義し、全パブリックメソッドを登録。
3. **`Makefile` ビルドパイプライン統合**:
   - `JS_SRCS` に `site/js/frameworks/graph-canvas.js` を追加。
   - `make build_js` で警告 0 件を確認。
4. **`site/dashboard.html` への接続**:
   - `GraphCanvasEngine` を利用可能にしつつ、既存の 52 件のテストがアサートしているプロパティ・関数シグネチャを 100% 維持。
5. **テストと品質検証**:
   - `tests/web/test_frontend_frameworks.py` に `GraphCanvasEngine` の単体テストを追加。
   - `tests/web/test_dashboard*.py` の全 52 テストが 100% PASS することを確認。
   - `make check_format` および `make static_analysis` の完全通過。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/graph-canvas.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] 力学シミュレーション、空間変換、描画パイプライン、HSM 操作管理、DisjointSet LCC が統合されていること
- [x] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [x] `tests/web/test_dashboard*.py` の全 52 テストが 100% PASS すること
- [x] `tests/web/test_frontend_frameworks.py` に新規テストが追加され 100% PASS すること
- [x] `make check_format` および `make static_analysis` が完全通過すること


