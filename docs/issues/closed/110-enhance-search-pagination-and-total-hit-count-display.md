---
ID: 110
種別: Improvement / Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 検索結果の総ヒット件数（Total Hits）返却・動的ページネーションおよび表示件数切替機能の実装 (ID: 110)

## 1. 概要 / Summary
現在、Web UI（`http://localhost:8000/?q=ペンテスト` 等）において検索を実行した際、UI 側の固定パラメータ `top_k=12` により検索結果が最大 12 件に制限され、件数表示も「検索結果 (12件)」と表示されてしまう課題が存在する。
実際にはインデックス内に該当する論文が数百件以上存在するにもかかわらず、ユーザーには「12件しか存在しない」と誤認される。

本 Issue では、検索バックエンド（`VectorEngine` / `SearchClient`）および API Gateway がクエリに一致した **「総ヒット件数（`total_hits` / `total_matching`）」** と **`offset`（ページ位置）** を算出してレスポンスに含めるとともに、Web UI において **「全 N 件中 A〜B 件を表示」の正確な件数表示**、**「もっと見る（Load More）」/ ページネーション**、および **「表示件数セレクタ（12件 / 24件 / 48件 / 100件）」** を実装した。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-14 (Search Engine Architecture)](../designs/DSN-14-search_engine_architecture.md): Multi-Field Postings, Hybrid Scoring, RRF Pipeline
  - [DSN-10 (UI/UX Presentation Architecture)](../designs/DSN-10-ui_presentation_architecture.md): Glassmorphism Design System, Dynamic Search Component
  - [DSN-07 (WSGI Web Server & API Gateway Architecture)](../designs/DSN-07-wsgi_web_server_architecture.md): JSON-RPC & REST API Routing

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### バックエンド (検索エンジン & API Gateway)
- [x] [src/search/vector_engine.py](../../src/search/vector_engine.py):
  - `search` メソッドに `offset: int = 0` 引数を追加。
  - スコアリング済み候補の全件数 `total_hits` を算出・保持し、返却辞書に `{"total_hits": total_hits, "offset": offset, "limit": limit, "results": paged_results}` を格納。
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py):
  - `handle_search` において `query_params` から `offset` / `page` および `top_k` / `limit` をパース。
  - レスポンス JSON に `total_hits`, `returned_count`, `offset`, `has_more` を含めて返却。

### フロントエンド (Web UI & スタイル)
- [x] [site/index.html](../../site/index.html):
  - 検索バーエリアに表示件数切替ドロップダウン (`<select id="pageSizeSelect">`) を追加。
  - 検索結果エリアの下部に「もっと見る」ボタン (`#loadMoreBtn`) およびページネーションコンテナ (`#loadMoreContainer`) を追加。
- [x] [site/app.js](../../site/app.js):
  - `performSearch(query, updateUrl, offset, append)` 関数を拡張。
  - 総件数表示フォーマット: `検索結果: 全 ${totalHits} 件中 1〜${currentLoadedCount} 件を表示`。
  - 「もっと見る」ボタン押下時のインクリメンタルカード追加描画。
  - URL クエリパラメータ（`?q=...&limit=24&offset=24`）の双方向バインディング。
- [x] [site/style.css](../../site/style.css):
  - ページネーションコントロール、ページサイズセレクタ、「もっと見る」ボタンの Glassmorphism スタイリング。

### テスト
- [x] [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py):
  - ページネーション・offset 制御および total_hits 返却の単体テスト。
- [x] [tests/web/test_web_server.py](../../tests/web/test_web_server.py):
  - `/api/search` の `offset`, `top_k`, `total_hits`, `has_more` レスポンス構造の網羅テスト。

---

## 4. セキュリティ & 品質要件 / Security & Quality Constraints

1. **入力パラメータ検証 & 境界値防御**:
   - `top_k` (limit): 最小 1、最大 100 に制限（DoS 攻撃およびメモリ肥大化防止）。
   - `offset` / `page`: 負数や不正な文字列が渡された場合は `0` / `1` へ安全にフォールバック。
2. **パフォーマンス・レイテンシ要件**:
   - `offset` 適用時もクエリレイテンシ 15ms 以内を維持。
3. **コード品質基準**:
   - 全変更モジュールにおいて Xenon 循環的複雑度（CC $\le 5$）**100% Rank A** を厳格遵守。
   - `make check_format`, `make py_compile`, `make test` が 100% PASS すること。

---

## 5. 詳細実装手順 / Step-by-Step Implementation Plan
Target Branch: `feat/110-enhance-search-pagination-and-total-hit-count`

### Step 1: `VectorEngine.search` のページネーション & 総件数対応
- `VectorEngine.search` のシグネチャを更新し、`total_hits` および `has_more` を算出。

### Step 2: API Gateway `handle_search` のレスポンス拡張
- `query_params` から `offset` (デフォルト 0) を安全に抽出。
- レスポンス JSON に `total_hits`, `offset`, `limit`, `has_more` を含めて返却。

### Step 3: Web UI (`index.html`, `app.js`, `style.css`) の強化
1. **表示件数セレクタ**:
   - `<select id="pageSizeSelect">` で `[12件, 24件, 48件, 96件]` を提供。
2. **結果カウント表示**:
   - `検索結果: 全 600 件中 1〜12 件を表示`
3. **「もっと見る (Load More)」ボタン**:
   - クリックで次ページの 12 件を API 取得し、既存グリッドの末尾にアニメーション付きで追加描画。

### Step 4: 単体テスト・統合テストの追加と品質ゲート検証
- `test_vector_engine_pagination_and_total_hits`: offset 指定によるページャー動作確認。
- `test_wsgi_app_search_pagination_and_total_hits`: `/api/search?q=malware&top_k=2&offset=0` の疎通検証。
- `make check_format` $\rightarrow$ `make py_compile` $\rightarrow$ `make static_analysis` $\rightarrow$ `make test` の全件パス確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `VectorEngine.search` が `offset` 引数を受け入れ、`total_hits` および `has_more` を正しく返却すること。
- [x] `/api/search` が `total_hits` (総マッチ件数) と `total` (返却件数) の両方を返すこと。
- [x] Web UI 上で「ペンテスト」を検索した際、「全 600 件中 1〜12 件を表示」と正確な母数が表示されること。
- [x] 「もっと見る」ボタンを押すことで、次の 12 件がリロードなしで連続追記されること。
- [x] 表示件数セレクタ（12 / 24 / 48 / 96）で件数を変更した際、指定件数で即座に再検索されること。
- [x] `limit` が最大 100 に制限され、不正な `offset` に対して安全にフォールバックすること。
- [x] 全 589+ 件のテストスイートが 100% PASS すること。
- [x] Xenon 循環的複雑度が全モジュールで **100% Rank A (CC $\le 5$)** を維持していること。
