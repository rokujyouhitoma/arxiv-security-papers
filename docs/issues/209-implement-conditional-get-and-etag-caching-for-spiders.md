---
ID: 209
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] ETag / If-Modified-Since 条件付きリクエストおよび HTTP 304 キャッシュ機構の実装 (ID: 209)

## 1. 概要 / Summary

CISA KEV カタログ（約 2MB の静的 JSON ファイル）をはじめとする定期巡回リソースにおいて、相手先サーバーへのトラフィック負荷を最小化し、不要な全量ダウンロードを避けるため、クローラー基盤に **RFC 7232 準拠の条件付きリクエスト (Conditional GET: `If-None-Match`, `If-Modified-Since`)** と **HTTP 304 Not Modified キャッシュ透過機構** を実装する。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](205-implement-cisa-kev-and-nvd-cve-spiders.md)
- 仕様: RFC 7232 (Hypertext Transfer Protocol -- Conditional Requests)
- 対象コンポーネント:
  - `src/spider/downloader/middleware.py` (`HttpCacheMiddleware`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/spider/downloader/middleware.py](../../src/spider/downloader/middleware.py) (`HttpCacheMiddleware` に ETag / Last-Modified 保持と 304 ハンドリングを追加)
- [ ] [tests/spider/test_conditional_cache.py](../../tests/spider/test_conditional_cache.py) (新規: 304 条件付きリクエストテスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/209-implement-conditional-get-and-etag-caching-for-spiders`

1. **メタデータキャッシュストレージ**:
   - キャッシュエントリに `Response` オブジェクトとともに `etag` および `last_modified` ヘッダーを保存。
2. **`process_request` における条件付きヘッダー付与**:
   - リクエスト対象 URL のキャッシュが存在する場合:
     - `ETag` があれば `If-None-Match` ヘッダーを自動付与。
     - `Last-Modified` があれば `If-Modified-Since` ヘッダーを自動付与。
3. **`process_response` における 304 処理**:
   - ステータスコードが `304 Not Modified` の場合、キャッシュ済みの前回ボディを持つレスポンス（ステータス 200 扱いまたは 304 のまま）を Spider に返し、ネットワークペイロードの取得をスキップ。
4. **テストの作成**:
   - 2回目アクセス時に `If-None-Match` が付与されること、304 受信時に前回のボディが利用されることの単体テスト。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] キャッシュ済み URL に対する再リクエスト時、`If-None-Match` / `If-Modified-Since` ヘッダーが正しくリクエストへ注入されること。
- [ ] サーバーが `304 Not Modified` を返した際、再ダウンロードなしに前回のキャッシュ内容を利用できること。
- [ ] 単体テストが PASS すること。
- [ ] `make check` がエラー 0 件で通過すること。
