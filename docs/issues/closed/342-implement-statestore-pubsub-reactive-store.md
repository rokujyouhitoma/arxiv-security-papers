---
ID: 342
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] StateStore: Pub/Sub 連動型軽量リアクティブ状態ストアの実装 (ID: 342)

## 1. 概要 / Summary

現在 `site/app.js` 内に 15 個以上のグローバル変数やフラグ（`currentView`, `selectedPaperId`, `activeFilters`, `isCrawling`, `searchQuery` 等）として散在している状態管理を、一元化された単一情報源（Single Source of Truth）としての軽量リアクティブ状態ストア `StateStore` を `site/js/frameworks/store.js` に実装した。

状態の更新（`set(key, val)`, `update(partialState)`）が発生した際、`Publisher`（Pub/Sub）と連動して変更されたキー単位でピンポイントにリスナーへ通知し、不要な画面全体再描画を回避する。また、デバッグ用の状態スナップショット履歴および Prototype Pollution 防御機構を内包する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.4, 8)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)
  - [Issue 339: ApiClient: 統一 HTTP 通信クライアント基盤の実装](closed/339-implement-apiclient-unified-http-gateway.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/frameworks/store.js`](../../site/js/frameworks/store.js) (新規)
- [x] [`site/externs.js`](../../site/externs.js) (`StateStoreInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`site/app.js`](../../site/app.js) (グローバル変数の `StateStore` 移行)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 脅威モデル分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **プロトタイプ汚染防御 (Prototype Pollution, CWE-1321)**:
   - 内部状態ストアに `Object.create(null)` を用い、`__proto__`, `constructor`, `prototype` といった特殊プロパティへの代入・更新を明示的に検証・拒絶する。
2. **参照リーク・外部不変性破壊の防止 (CWE-374)**:
   - `getState()` が返すスナップショットは浅い複製（Shallow Copy）を行い、外部コンポーネントによる内部オブジェクトの直接改ざんを抑止する。
3. **安全なサブスクリプション解除とメモリリーク防止 (CWE-401)**:
   - `subscribe(key, fn)` は購読解除関数（`unsubscribe()`）を返却し、画面破棄時・コンポーネントアンマウント時の確実なリスナー解放を保証する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/342-implement-statestore-pubsub-reactive-store`

1. **`StateStore` クラスの設計と実装 (`site/js/frameworks/store.js`)**:
   - `constructor(initialState = {}, publisher = null)`
   - プロトタイプ汚染防止のキーバリデーション
   - メソッド: `getState()`, `get(key, defaultValue)`, `set(key, value)`, `update(partialState)`, `subscribe(key, callback)`, `reset(initialState)`
   - 更新時にキーごとのイベント `state:change:${key}` および全体イベント `state:changed` を `Publisher` 経由で発火
2. **Closure Compiler 適合 (`site/externs.js`, `Makefile`)**:
   - `site/externs.js` に `StateStoreInterface` の型シグネチャを宣言
   - `Makefile` の `JS_SRCS` に `site/js/frameworks/store.js` を追加
3. **`site/app.js` との連携**:
   - `Locator.register('stateStore', appStateStore)` による DI 登録
   - `activeTag`, `activePeriod`, `currentLimit` 等のグローバル変数を `appStateStore` へ同期
4. **テストスイートの拡張 (`tests/web/test_frontend_frameworks.py`)**:
   - バンドル整合性、シンボル抽出、およびプロトタイプ汚染ブロックの検証

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/store.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] `site/externs.js` に `StateStore` の型定義が追加され、`make build_js` で警告 0 件であること
- [x] プロトタイプ汚染キー（`__proto__` 等）の拒絶が正しく機能すること
- [x] 状態変更時のキー単位通知およびスナップショット複製が正常に行われること
- [x] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [x] `make verify_quality` が完全通過すること

