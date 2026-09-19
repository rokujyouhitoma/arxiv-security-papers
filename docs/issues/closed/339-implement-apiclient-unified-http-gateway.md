---
ID: 339
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ApiClient: 統一 HTTP 通信クライアント基盤の実装 (ID: 339)

## 1. 概要 / Summary

現在 `site/app.js` 内で散発的に呼び出されている `fetch()` API コールを集約・共通化し、統一的なエラーハンドリング、JSON レスポンスパース、タイムアウト制御（AbortController）、CSRF ヘッダー付与、および認証トークン・相関 ID（Correlation ID）伝播を司る高凝縮な通信クラアント `ApiClient` を `site/js/frameworks/api-client.js` に実装した。

これにより、各 UI 画面・コンポーネントにおける通信処理のボイラープレートを排除し、ネットワーク切断や HTTP 4xx/5xx エラー時の統一的なユーザーフィードバック（トースト通知連携・リトライ）を実現した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-27: モジュール型 Web フロントエンド・フレームワーク ＆ クライアントアーキテクチャ設計仕様書](../designs/DSN-27-modular_frontend_framework_and_client_architecture.md) (セクション 5.1, 8)
  - [DSN-09: API Gateway ＆ UI プレゼンテーション包括設計書](../designs/DSN-09-web_gateway_and_presentation.md)
- 関連 Issue:
  - [Issue 338: Webフロントエンド設計・アーキテクチャの刷新と yuzora frameworks の統合](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`site/js/frameworks/api-client.js`](../../site/js/frameworks/api-client.js) (新規)
- [x] [`site/externs.js`](../../site/externs.js) (`ApiClientInterface` 型定義追加)
- [x] [`Makefile`](../../Makefile) (`JS_SRCS` 登録、`build_js` 検証)
- [x] [`site/app.js`](../../site/app.js) (`fetch` 呼び出し箇所の `ApiClient` 移行)
- [x] [`tests/web/test_frontend_frameworks.py`](../../tests/web/test_frontend_frameworks.py) (単体・統合テストケース追加)

---

## 4. 脅威モデル分析とセキュリティ要件 (Threat Model & Security Requirements)

1. **不正 URL リダイレクト / SSRF 防御 (CWE-918)**:
   - `ApiClient` に渡される URL は同一オリジン内の相対パス（`/api/...`）に限定し、プロトコル相対 URL（`//attacker.com`）や絶対外部 URL の混入を構造的に拒絶する。
2. **リソース枯渇 / ハング防御 (CWE-400)**:
   - 全てのリクエストに `AbortController` による厳格なタイムアウト（デフォルト 15,000ms）を適用し、未完了の保留接続によるブラウザスレッドや接続プールの枯渇を防止する。
3. **エラー情報の安全な伝播 (CWE-209)**:
   - サーバー側の内部スタックトレースや機微情報が UI に生テキストとして漏洩しないよう、`ApiError` クラス内でユーザー向けメッセージとデバッグ情報を分離する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/339-implement-apiclient-unified-http-gateway`

1. **`ApiClient` クラスの設計と実装 (`site/js/frameworks/api-client.js`)**:
   - `constructor(baseUrl = '', defaultOptions = {})`
   - メソッド: `get(path, params, options)`, `post(path, body, options)`, `request(path, options)`
   - URL 検証ロジック（プロトコル相対 URL や外部 URL の拒絶）
   - `AbortController` によるタイムアウト制御
   - `ApiError` クラス（`status`, `statusText`, `data`, `url` をカプセル化）
   - 成功・失敗時の Publisher イベント通知（`api:success`, `api:error`）
2. **Closure Compiler 適合 (`site/externs.js`, `Makefile`)**:
   - `site/externs.js` に `ApiClientInterface` 型シグネチャを宣言
   - `Makefile` の `JS_SRCS` に `site/js/frameworks/api-client.js` を追加
3. **`site/app.js` との連携**:
   - `Locator.set('apiClient', new ApiClient())` による DI 登録
   - `/api/stats`, `/api/paper/...` などの主要 API コールを `ApiClient` 経由にリファクタリング
4. **テストスイートの拡張 (`tests/web/test_frontend_frameworks.py`)**:
   - Python による Closure Compiler バンドル検証、構文検証、クラス抽出テスト

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `site/js/frameworks/api-client.js` が実装され、JSDoc 型アノテーションが付与されていること
- [x] `site/externs.js` に `ApiClient` / `ApiError` の型定義が追加され、`make build_js` で警告 0 件であること
- [x] 相対パス検証およびタイムアウト（AbortController）が実装されていること
- [x] `tests/web/test_frontend_frameworks.py` にテストが追加され `pytest tests/web/` が 100% PASS すること
- [x] `make verify_quality` (format, static_analysis, test) が完全通過すること

