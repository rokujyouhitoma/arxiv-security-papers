---
ID: 340
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] SSEStreamManager: SSE 接続・指数バックオフ再接続マネージャーの実装 (ID: 340)

## 1. 概要 / Summary

現在 `site/app.js` 内で直に生成・制御されている `EventSource`（リアルタイム通知・クロール進捗・システムイベントストリーム）の接続管理を独立したモジュール `SSEStreamManager` として `site/js/frameworks/sse-manager.js` に集約・実装する。

ネットワーク一時切断やサーバー再起動時の指数バックオフ（Exponential Backoff with Jitter）付き自動再接続、タブ非アクティブ化時（`document.visibilitychange`）の一時停止とフォアグラウンド復帰時の即時同期、接続状態（`DISCONNECTED`, `CONNECTING`, `CONNECTED`, `RECONNECTING`）の `Publisher` イベント配信を包括管理する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.2, 8)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
  - [DSN-12: 汎用プロセススーパーバイザー & 調停基盤包括設計書](../designs/DSN-12-process_supervisor_and_arbiter.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)
  - [Issue 339: ApiClient: 統一 HTTP 通信クライアント基盤の実装](closed/339-implement-apiclient-unified-http-gateway.md)
  - [Issue 342: StateStore: Pub/Sub 連動型軽量リアクティブ状態ストアの実装](closed/342-implement-statestore-pubsub-reactive-store.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/sse-manager.js`](../../site/js/frameworks/sse-manager.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`SSEStreamManagerInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (`EventSource` 直接参照の `SSEStreamManager` 移行)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (単体・統合テストケース追加)

---

## 4. 脅威モデル分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **接続枯渇 / リソースリーク防御 (CWE-400, CWE-772)**:
   - バックグラウンドタブやページ離脱時に `close()` を確実に呼び出し、サーバー側ワーカープロセスやソケットスレッドの枯渇を防止する。
2. **サンダリングハード（Thundering Herd）防御**:
   - サーバー再起動や障害復旧時に大量クライアントが一斉接続しないよう、指数バックオフにランダムなジッター（Jitter, 0.2〜0.5）を付与する。
3. **安全な JSON ペイロードパース (CWE-20)**:
   - `e.data` のパース処理は例外安全な `try-catch` で保護し、壊れたストリームチャンクによるブラウザ UI クラッシュを完全防止する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/340-implement-ssestreammanager-with-exponential-backoff`

1. **`SSEStreamManager` クラスの設計と実装 (`site/js/frameworks/sse-manager.js`)**:
   - `constructor(endpoint, options = {}, publisher = null)`
   - 状態定義: `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `RECONNECTING`
   - メソッド: `connect()`, `disconnect()`, `getState()`, `on(eventType, handler)`, `off(eventType, handler)`
   - 指数バックオフ計算アルゴリズム（初期 1s、最大 30s、係数 2.0、Jitter 0.2）
   - タブ可視性連動（`visibilitychange`）による自動一時停止・復帰
   - 受信した各 SSE イベントを登録ハンドラーおよび `Publisher.publish('sse:event', ...)` へ転送
2. **Closure Compiler 適合 (`site/externs.js`, `Makefile`)**:
   - `site/externs.js` に `SSEStreamManagerInterface` の型シグネチャを宣言
   - `Makefile` の `JS_SRCS` に `site/js/frameworks/sse-manager.js` を追加
3. **`site/app.js` との統合**:
   - `appLocator.register('sseManager', appSSEManager)` による DI 登録
   - 既存の `initSseLiveStream` を `SSEStreamManager` インスタンス制御にリファクタリング
4. **テストスイートの拡張 (`tests/web/test_frontend_frameworks.py`)**:
   - バンドル整合性、シンボル抽出、再接続数理モデルの検証

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/sse-manager.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/externs.js` に `SSEStreamManager` の型定義が追加され、`make build_js` で警告 0 件であること
- [ ] 指数バックオフ（Jitter 付き）およびタブ可視性連動が実装されていること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [ ] `make verify_quality` が完全通過すること

