---
ID: 349
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] `ApiClient` & `ARCCache`: 残存生 `fetch()` の一掃、HTTP通信一元化、および適応型キャッシュ (`ARCCache(256)`) 統合 (ID: 349)

## 1. 概要 / Summary
`site/app.js` (8箇所) および `site/dashboard.html` (4箇所) に残存している生の `fetch()` 呼び出しを、`site/js/frameworks/api-client.js` で構築された統一 HTTP クライアント `ApiClient` に置き換える。
同時に、`appApiClient` の初期化時に `ARCCache(256)` を注入し、適応型置換キャッシュ (Adaptive Replacement Cache, FAST '03) による GET リクエストの重複除外と高速キャッシュを有効化する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [339-implement-apiclient-unified-http-gateway.md](closed/339-implement-apiclient-unified-http-gateway.md)
  - [346-port-arc-cache-to-frontend-metadata-caching.md](closed/346-port-arc-cache-to-frontend-metadata-caching.md)
  - [338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md](closed/338-refactor-web-frontend-architecture-and-import-yuzora-frameworks.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [site/app.js](../site/app.js) (`appApiClient` 初期化、8箇所の生 `fetch`)
- [ ] [site/dashboard.html](../site/dashboard.html) (4箇所の生 `fetch`、`ApiClient` インスタンス連携)
- [ ] [site/externs.js](../site/externs.js) (Closure Compiler 向け extern 定義)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/349-integrate-apiclient-and-arc-cache`

1. `site/app.js`:
   - `appApiClient` を `new ApiClient('', { cache: new ARCCache(256) }, appPublisher)` として初期化。
   - 以下の 8 箇所の生 `fetch()` を `appApiClient.get()` / `appApiClient.post()` に換装:
     - L565: 検索 API (`/api/search?q=...`)
     - L826: トレンド API (`/api/trends?period=...`)
     - L880: MCP アクション (`/api/mcp`)
     - L1073: ライフサイクルテレメトリ (`/api/system/lifecycle`)
     - L1463: グラフメッシュ (`/api/graph/mesh`)
     - L1709: スパイダーステータス (`/api/spiders/status`)
     - L1771: スパイダー実行ログ (`/api/spiders/logs/...`)
     - L1839: スパイダー手動トリガー (`/api/spiders/trigger`)
2. `site/dashboard.html`:
   - `window.dashboardApiClient = new ApiClient('', { cache: new ARCCache(256) });` を初期化。
   - 以下の 4 箇所の生 `fetch()` を `dashboardApiClient.get()` に換装:
     - L2966: `/api/graph/query`
     - L3022: `/api/graph/cti-mesh`
     - L3054: `/api/graph/schema`
     - L4423: `/api/graph/mesh`
3. タイムアウト (既定10秒) とエラーハンドリング (`ApiError`) を統一。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `site/app.js` および `site/dashboard.html` から生 `fetch()` が完全に排除され、すべて `ApiClient` 経由になっていること。
- [ ] `ARCCache(256)` が正しく注入され、同一エンドポイントへの GET 要求でキャッシュヒット・通信抑制が機能すること。
- [ ] Google Closure Compiler (`python scripts/compile_frontend.py`) がエラー 0 件で通過すること。
- [ ] 既存の全回帰テスト (`pytest tests/web/`) 175件が 100% PASS すること。
