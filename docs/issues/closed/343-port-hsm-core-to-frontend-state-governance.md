---
ID: 343
種別: Feature
優先度: High
ステータス: Closed (完了)
完了日: 2026-09-19
---

# [FEAT] HierarchicalStateMachine (HSM): src/core/hsm/ の JS 移植と状態管理統合 (ID: 343)

## 1. 概要 / Summary

バックエンド `src/core/hsm/`（`engine.py`, `tree.py`）で構築されているゼロ外部依存の階層型ステートマシン（Hierarchical State Machine, HSM）の設計思想とコアアルゴリズムを、Web フロントエンド向け純粋 JavaScript モジュール `site/js/frameworks/hsm.js` に移植・実装する。

UI の複合状態（例: ナレッジグラフ画面における `Normal.Idle`, `Normal.Panning`, `Normal.DraggingNode`, `Inspecting` などの階層状態）および SSE ストリーミング接続のライフサイクル管理において、親状態へのイベントバブリング、`entry` / `exit` アクションの厳密な順序実行、不正な並行遷移の防止を保証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 6.1, 8)
  - [DSN-23: ゼロ外部依存・高信頼階層型ステートマシン（HSM）基盤およびシステム全域ライフサイクル統制設計仕様書](../designs/DSN-23-hierarchical_state_machine_and_lifecycle_governance.md)
  - [DSN-14: 論文・脅威ナレッジグラフ & エンジニアリングダッシュボード設計書](../designs/DSN-14-graph_engineering_dashboard.md)
- 移植元コード:
  - `src/core/hsm/engine.py`
  - `src/core/hsm/tree.py`
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/frameworks/hsm.js`](../../site/js/frameworks/hsm.js) (新規)
- [x] [`site/externs.js`](../../site/externs.js) (`HierarchicalStateMachineInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`site/js/frameworks/sse-manager.js`](../../site/js/frameworks/sse-manager.js) (HSM 連動)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/343-port-hsm-core-to-frontend-state-governance`

1. **`HierarchicalStateMachine` クラスの設計と実装**:
   - 状態ツリー定義: 各状態ノードは `name`, `parent`, `initialChild`, `onEntry`, `onExit`, `transitions` を保持
   - メソッド: `dispatch(event, payload)`, `sendEvent()`, `isInState(stateId)`, `getStatePath()`, `getCurrentStatePath()`, `forceTransition()`
   - LCCA（Lowest Common Composite Ancestor）アルゴリズムによる、退出（exit）と進入（entry）アクションの正確な連鎖実行
   - ガード条件（Guards）の評価とアクション実行コンテキスト
   - `HierarchicalStateMachine.fromConfig(config)` による宣言的ステートマシン構築
2. **Closure Compiler 適合**:
   - `site/externs.js` に `HierarchicalStateMachineInterface` の型定義を追加
3. **適用とテスト**:
   - `site/js/frameworks/sse-manager.js` への HSM ライフサイクル統制の組み込み
   - `tests/web/test_frontend_frameworks.py` に Node.js 連携による LCCA / 階層遷移 / ガード / イベントバブリング統合テストを追加

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/hsm.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] `src/core/hsm/` と同等の階層遷移・LCA 計算・entry/exit アクション順序が担保されていること
- [x] `site/externs.js` に型定義が追加され、`make build_js` で警告 0 件であること
- [x] `tests/web/test_frontend_frameworks.py` に階層遷移シナリオのテストが追加され 100% PASS すること
- [x] `make check_format` および `make static_analysis` が完全通過すること
