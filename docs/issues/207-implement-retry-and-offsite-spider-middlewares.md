---
ID: 207
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Spider基盤における HTTP 429/503 指数バックオフ再試行 (RetryMiddleware) と SSRF ドメイン防御 (OffsiteMiddleware) の実装 (ID: 207)

## 1. 概要 / Summary

[Issue 205](205-implement-cisa-kev-and-nvd-cve-spiders.md) の外部インテリジェンス（NVD CVE API 2.0 / CISA KEV）収集において不可欠となる、通信耐障害性とセキュリティ防護をクローラー基盤（`src/spider/`）に導入する。

1. **HTTP 429 / 503 指数バックオフ自動再試行ミドルウェア (`RetryMiddleware`)**:
   - NVD などの外部 REST API から `429 Too Many Requests`, `503 Service Unavailable`, `504 Gateway Timeout` を受信した際、即座にリクエストを失敗させず、指数バックオフ（初期待機 10 秒、最大 3 回リトライ）を適用して待機後に `Scheduler` へ再投入する。
   - レスポンスヘッダーに `Retry-After` が含まれる場合はその指定秒数を最優先で尊重する。
2. **SSRF 防御 & 外部ドメイン逸脱防止ミドルウェア (`OffsiteMiddleware`)**:
   - 各 Spider の `allowed_domains` 属性を検証し、許可されていないドメインへのリダイレクトや `Request` を自動検出して遮断する。
   - これにより、悪意ある外部リダイレクトによる SSRF や、意図しない他ホストへのスクレイピングを強制的に防ぐ。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](205-implement-cisa-kev-and-nvd-cve-spiders.md)
- セキュリティ要件: NIST SP 800-53 SC-5 (DoS Protection), SC-7 (Boundary Protection), RFC 6585 (HTTP 429)
- 対象コンポーネント:
  - `src/spider/downloader/middleware.py` (`RetryMiddleware`, `OffsiteMiddleware`)
  - `src/spider/runner.py` (`_build_spider_middlewares`)
  - `src/spider/core/engine.py` (ミドルウェア再試行フック連携)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/spider/downloader/middleware.py](../../src/spider/downloader/middleware.py) (`RetryMiddleware`, `OffsiteMiddleware` の追加)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (ミドルウェアスタックへの `OffsiteMiddleware`, `RetryMiddleware` の標準統合)
- [ ] [tests/spider/test_retry_and_offsite_middlewares.py](../../tests/spider/test_retry_and_offsite_middlewares.py) (新規: ユニットテスト)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/207-implement-retry-and-offsite-spider-middlewares`

1. **`RetryMiddleware` の設計と実装**:
   - リトライ対象ステータスコード: `{429, 500, 502, 503, 504}`
   - `max_retries = 3`, `backoff_factor = 2.0`, `initial_delay = 10.0`
   - `process_response(request, response, spider)`:
     - リトライ対象ステータスを受信した場合、`request.meta['retry_times']` をインクリメント。
     - `Retry-After` ヘッダーがあれば解析（秒数または HTTP-Date）。なければ `initial_delay * (backoff_factor ** (retry_times - 1))` でスリープ。
     - エンジンのスケジューラへ `Request` を再エンキュー。
2. **`OffsiteMiddleware` の設計と実装**:
   - `process_request(request, spider)`:
     - `spider.allowed_domains` が定義されている場合、`request.url` のホスト名がドメイン（またはサブドメイン）に合致するか判定。
     - 合致しない場合はリクエストをスキップ（None またはエラーレスポンスを返却）しログを記録。
3. **Runner へのミドルウェア組み込み**:
   - `_build_spider_middlewares` にて `OffsiteMiddleware` と `RetryMiddleware` を適切な順序で追加。
4. **ユニットテストの作成**:
   - 429 受信時のバックオフ待機と再試行回数上限（3回で停止）の検証。
   - `allowed_domains` 外のホストへのリクエスト遮断の検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] HTTP 429 / 503 受信時に自動的に待機と再試行が行われ、一時的な障害から自己復旧すること。
- [ ] `allowed_domains` に含まれない不正ホストへのリクエストが安全にドロップされること。
- [ ] 外部通信を伴わないモックテストが全件 PASS すること。
- [ ] `make check` (mypy --strict, flake8, radon, xenon Grade A) がエラー 0 件で通過すること。
