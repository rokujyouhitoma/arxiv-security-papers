---
ID: 339
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ApiClient: 統一 HTTP 通信クライアント基盤の実装 (ID: 339)

## 1. 概要 / Summary

現在 `site/app.js` 内で散発的に呼び出されている `fetch()` API コールを集約・共通化し、統一的なエラーハンドリング、JSON レスポンスパース、タイムアウト制御（AbortController）、CSRF ヘッダー付与、および認証トークン・相関 ID（Correlation ID）伝播を司る高凝縮な通信クラアント `ApiClient` を `site/js/frameworks/api-client.js` に実装する。

これにより、各 UI 画面・コンポーネントにおける通信処理のボイラープレートを排除し、ネットワーク切断や HTTP 4xx/5xx エラー時の統一的なユーザーフィードバック（トースト通知連携・リトライ）を実現する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.1, 8)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`site/js/frameworks/api-client.js`](../../site/js/frameworks/api-client.js) (新規)
- [ ] [`site/externs.js`](../../site/externs.js) (`ApiClientInterface` 型定義追加)
- [ ] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [ ] [`site/app.js`](../../site/app.js) (`fetch` 呼び出し箇所の `ApiClient` 移行)
- [ ] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (単体・統合テストケース追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/339-implement-apiclient-unified-http-gateway`

1. **`ApiClient` クラスの設計と実装**:
   - `constructor(baseUrl = '', defaultOptions = {})`
   - メソッド: `get(path, params, options)`, `post(path, body, options)`, `request(path, options)`
   - `AbortController` によるデフォルト 15 秒タイムアウト制御
   - レスポンスステータスに応じた `ApiError`（`status`, `statusText`, `data` を保持）の送出
   - `Locator.set('apiClient', new ApiClient())` による DI 登録
2. **Closure Compiler 適合**:
   - `site/externs.js` に `ApiClient` および `ApiClientInterface` の型シグネチャを明記
3. **既存呼び出しの移行**:
   - `/api/search`, `/api/paper`, `/api/telemetry`, `/api/health` などの既存 `fetch` を `ApiClient` 経由に置き換え

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `site/js/frameworks/api-client.js` が実装され、JSDoc 型アノテーションが付与されていること
- [ ] `site/externs.js` に `ApiClient` の型定義が追加され、`make build_js` で警告 0 件であること
- [ ] タイムアウトおよび HTTP 4xx/5xx エラー時の例外処理と Publisher イベント連携が正常に機能すること
- [ ] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [ ] `make verify_quality` (format, static_analysis, test) が完全通過すること
