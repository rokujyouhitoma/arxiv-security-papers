---
ID: 342
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] StateStore: Pub/Sub 連動型軽量リアクティブ状態ストアの実装 (ID: 342)

## 1. 概要 / Summary

現在 `site/app.js` 内に 15 個以上のグローバル変数やフラグ（`currentView`, `selectedPaperId`, `activeFilters`, `isCrawling`, `searchQuery` 等）として散在している状態管理を、一元化された単一情報源（Single Source of Truth）としての軽量リアクティブ状態ストア `StateStore` を `site/js/frameworks/store.js` に実装する。

状態の更新（`setState(updaterOrPartial)`）が発生した際、`Publisher`（Pub/Sub）と連動して変更されたキー単位でピンポイントにリスナーへ通知し、不要な画面全体再描画を回避する。また、デバッグ用の状態スナップショット履歴および Prototype Pollution 防御機構を内包する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.4, 8)
  - [DSN-21: エンタープライズ統合デザインシステム ＆ クラウドコンソール UI 包括設計書](../designs/DSN-21-enterprise_design_system_and_unified_console.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/store.js`](../../site/js/frameworks/store.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`StateStoreInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (グローバル変数の `StateStore` 移行)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/342-implement-statestore-pubsub-reactive-store`

1. **`StateStore` クラスの設計と実装**:
   - `constructor(initialState = {}, publisher = null)`
   - 内部状態ストレージは `Object.create(null)` による Prototype Pollution 完全遮断
   - メソッド: `getState()`, `get(key, defaultValue)`, `set(key, value)`, `update(partialState)`, `subscribe(key, callback)`
   - 更新時にキーごとのイベント `state:change:${key}` および全体イベント `state:changed` を `Publisher` 経由で発火
   - イミュータブルなスナップショット返却（浅いコピー保護）
2. **Closure Compiler 適合**:
   - `site/externs.js` に `StateStore` の型定義を追加
3. **`site/app.js` の状態移行**:
   - `Locator.set('stateStore', store)` で公開し、ビュー間・コンポーネント間での状態共有を統一

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/store.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/externs.js` に `StateStore` の型定義が追加され、`make build_js` で警告 0 件であること
- [ ] 状態変更時のキー単位通知およびイミュータブルアクセスの検証テストが成功すること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
