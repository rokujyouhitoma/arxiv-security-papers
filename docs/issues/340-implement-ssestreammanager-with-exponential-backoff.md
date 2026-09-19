---
ID: 340
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] SSEStreamManager: SSE 接続・指数バックオフ再接続マネージャーの実装 (ID: 340)

## 1. 概要 / Summary

現在 `site/app.js` 内で直に生成されている `EventSource`（リアルタイム通知・クロール進捗・システムイベントストリーム）の接続管理を独立したモジュール `SSEStreamManager` として `site/js/frameworks/sse-manager.js` に集約・実装する。

ネットワーク一時切断やサーバー再起動時の指数バックオフ（Exponential Backoff with Jitter）付き自動再接続、タブ非アクティブ化時（`document.visibilitychange`）の一時停止とフォアグラウンド復帰時の即時同期、接続状態（`CONNECTING`, `OPEN`, `CLOSED`, `RECONNECTING`）の `Publisher` イベント配信を包括管理する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.2, 8)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
  - [DSN-12: 汎用プロセススーパーバイザー & 調停基盤包括設計書](../designs/DSN-12-process_supervisor_and_arbiter.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/sse-manager.js`](../../site/js/frameworks/sse-manager.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`SSEStreamManagerInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (`EventSource` 直接参照の `SSEStreamManager` 移行)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (単体・統合テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/340-implement-ssestreammanager-with-exponential-backoff`

1. **`SSEStreamManager` クラスの設計と実装**:
   - `constructor(endpoint, options = {})`
   - メソッド: `connect()`, `disconnect()`, `subscribe(eventType, callback)`, `getState()`
   - 指数バックオフ計算アルゴリズム（初期 1s、最大 30s、jitter 係数 0.2）
   - タブ可視性連動（`visibilitychange`）によるバックグラウンド接続負荷抑制
   - 受信した各 SSE イベントを `Publisher.publish('sse:event', data)` へ転送
2. **Closure Compiler 適合**:
   - `site/externs.js` に `SSEStreamManager` の型定義を追加
3. **`site/app.js` への統合**:
   - `Locator.set('sseManager', new SSEStreamManager('/api/stream'))` による登録とライフサイクル制御

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/sse-manager.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/externs.js` に `SSEStreamManager` の型定義が追加され、`make build_js` で警告 0 件であること
- [ ] ネットワーク切断時の指数バックオフ再接続ロジックが正常にシミュレート・動作すること
- [ ] タブ非表示・表示時の接続リソース解放・再接続が正常に行われること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [ ] `make verify_quality` が完全通過すること
