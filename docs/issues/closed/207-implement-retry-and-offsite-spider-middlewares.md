---
ID: 207
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Spider基盤における HTTP 429/503 指数バックオフ再試行 (RetryMiddleware) と SSRF ドメイン防御 (OffsiteMiddleware) の実装 (ID: 207)

## 1. 概要 / Summary

[Issue 205](205-implement-cisa-kev-and-nvd-cve-spiders.md) の外部脅威インテリジェンス（NVD CVE API 2.0 / CISA KEV）収集および今後の大規模分散Webクローリングにおいて不可欠となる、通信耐障害性とセキュリティ境界防護をクローラー基盤（`src/spider/`）に導入する。

1. **SSRF 防護 & 外部ドメイン逸脱防止ミドルウェア (`OffsiteMiddleware`)**:
   - 各 Spider の `allowed_domains` 属性を検証し、許可されていない外部ドメインや内部ネットワーク（プライベートIP、リンクローカル、ループバック等）へのリクエストをダウンローダー実行前に水際遮断（HTTP 403 / `X-Blocked-By: OffsiteMiddleware`）する。
   - これにより、悪意ある外部リダイレクトや未検証リンク追従による SSRF (Server-Side Request Forgery) や意図しない外部ホストへのスクレイピングをゼロ外部依存で強制的に防ぐ。
2. **HTTP 429 / 503 指数バックオフ自動再試行ミドルウェア (`RetryMiddleware`)**:
   - NVD 等の外部 REST API や Web サーバーから一時的なレート制限（`429 Too Many Requests`）やサーバー過負荷（`500`, `502`, `503`, `504`）を受信した際、即座にリクエストを破棄・失敗させず、指数バックオフ（初期 2.0s、係数 2.0、最大 3 回リトライ）を適用して自律的に通信を再試行・自己修復する。
   - レスポンスヘッダーに `Retry-After`（秒数指定）が含まれる場合はその指定値を最優先で待機時間として採用する。

---

## 2. 背景・動機 / Motivation & Background

- **NVD CVE API 2.0 の厳格なレート制限**: NVD API は API キー未指定時 5リクエスト/30秒（0.16 req/sec）、キー指定時でも 50リクエスト/30秒と極めて厳格であり、一時的なスパイクやバックエンド過負荷により HTTP 429 / 503 が頻発する。これらを単純エラーとして破棄すると CTI 収集の欠損を招くため、自動リトライ機構が必須である。
- **Web クローリングにおける境界防護欠如の危険性**: スパイダーが HTML 内の外部ハイパーリンク（`href`）を無制限に追従すると、攻撃者が細工したページにより `http://169.254.169.254`（クラウドメタデータ）や `http://127.0.0.1:8000`（内部管理ポート）への SSRF 攻撃を誘発される恐れがある。Scrapy 等の標準クローラーと同様に `allowed_domains` による厳格なドメイン境界ガードレールを最前線に配置する必要がある。

---

## 3. トレーサビリティ / Traceability

- **関連 Issue**:
  - [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](205-implement-cisa-kev-and-nvd-cve-spiders.md)
  - [Issue 206: Response.json プロパティ追加と Spider 設定伝搬機構実装](closed/206-add-response-json-and-spider-delay-propagation.md)
- **セキュリティ基準 & 標準規格**:
  - NIST SP 800-53 Rev. 5:
    - **SC-5 (Denial of Service Protection)**: リトライ頻度・上限の指数バックオフ制御
    - **SC-7 (Boundary Protection)**: 未許可ドメイン・内部ネットワークへの通信遮断
    - **SI-10 (Information Input Validation)**: ホスト名・スキームの厳格検証
  - RFC 6585 (Additional HTTP Status Codes: 429 Too Many Requests)
  - RFC 9110 (HTTP Semantics: Section 10.2.3 `Retry-After`)
  - OWASP Top 10: A10:2021 (Server-Side Request Forgery - SSRF)
- **設計書**:
  - [DSN-06 ゼロ外部依存・大規模分散Webクローラー＆スパイダー基盤包括的アーキテクチャ設計書](../designs/DSN-06-distributed_spider_and_crawler.md) (Section 1.1.3, 4.5, 7.3)
- **対象コンポーネント**:
  - `src/spider/downloader/middleware.py` (`OffsiteMiddleware`, `RetryMiddleware`)
  - `src/spider/runner.py` (`_build_spider_middlewares`, `run_spider`)
  - `tests/spider/test_retry_and_offsite_middlewares.py` (新規テストスイート)

---

## 4. 脅威分析・セキュリティ要件 (Threat Modeling & Security)

| 脅威 / リスク | CWE 分類 | 深刻度 | 防護メカニズム / 緩和策 |
| :--- | :--- | :---: | :--- |
| **外部リダイレクト/細工URLによる内部SSRF** | CWE-918 (SSRF) | **High** | `OffsiteMiddleware` がリクエスト発行前に URL ホスト名を抽出し、`spider.allowed_domains` への適合性（完全一致またはサブドメイン照合）を検証。不一致時は 403 レスポンスで即座に遮断しダウンローダーへの到達を阻止。 |
| **内部ループバック/メタデータAPIへのアクセス** | CWE-918 / CWE-200 | **High** | `127.0.0.1`, `localhost`, `::1`, `169.254.169.254` 等の内部ホストも `allowed_domains` に含まれない限りデフォルトで完全に遮断。 |
| **HTTP 429 無限リトライによる相手先 DoS / Self-DoS** | CWE-400 (Uncontrolled Resource Consumption) | **Medium** | `RetryMiddleware` で `max_retry_times=3` の厳格な上限を設定。指数バックオフ ($T = \text{initial\_delay} \times \text{backoff\_factor}^{\text{retries}}$) または `Retry-After` 秒数の遵守を強制。 |
| **偽装・異常な `Retry-After` によるプロセスハング** | CWE-400 | **Low** | `Retry-After` の解析において最大許容待機時間（`max_retry_delay = 60.0s`）をキャップとし、異常な巨大数値や日付パース失敗時の安全なフォールバックを実装。 |

---

## 5. アーキテクチャと詳細設計 / Architecture & Detailed Design

### 5.1 ミドルウェア連鎖順序 (Middleware Pipeline Order)

Engine の入出力ライフサイクル（リクエスト送信時は正順、レスポンス受信時は逆順）に準拠した最適なミドルウェア連鎖：

```
[Request 発行フロー]
Engine -> OffsiteMiddleware (最前線でドメイン遮断)
       -> UserAgentMiddleware (ヘッダー注入)
       -> RobotsTxtMiddleware (規則照合)
       -> AutoThrottlePolicy (ドメイン間隔制御)
       -> HttpCacheMiddleware (キャッシュ照合)
       -> AsyncHttpDownloader (ソケット通信)

[Response 受信フロー]
AsyncHttpDownloader -> HttpCacheMiddleware (200 OK 保存)
                    -> AutoThrottlePolicy (レイテンシ計測)
                    -> RobotsTxtMiddleware (通過)
                    -> UserAgentMiddleware (通過)
                    -> RetryMiddleware (最後段で 429/5xx を検知し必要に応じ再試行)
                    -> Engine
```

### 5.2 `OffsiteMiddleware` の設計仕様
- **ドメイン照合アルゴリズム**:
  1. `allowed_domains: Sequence[str] = getattr(spider, "allowed_domains", [])` を取得。
  2. `allowed_domains` が未定義または空の場合は、制限なし（全ドメイン通過: `return None`）とする。
  3. `urllib.parse.urlsplit(request.url).hostname` からホスト名を取得（小文字化）。
  4. ホスト名が存在しない、あるいは `host != domain` かつ `not host.endswith("." + domain)` の場合、ドメイン外と判定。
  5. 遮断時はダウンローダーを起動させず、以下の合成 `Response` を即座に返却：
     ```python
     Response(
         url=request.url,
         status_code=403,
         headers={"X-Blocked-By": "OffsiteMiddleware"},
         body=b"Blocked by OffsiteMiddleware: Host not in allowed_domains",
         request=request,
     )
     ```

### 5.3 `RetryMiddleware` の設計仕様
- **クラス構成**:
  ```python
  class RetryMiddleware:
      def __init__(
          self,
          max_retry_times: int = 3,
          initial_delay: float = 2.0,
          backoff_factor: float = 2.0,
          max_delay: float = 60.0,
          retry_http_codes: Optional[Set[int]] = None,
          downloader: Optional[AsyncHttpDownloader] = None,
      ) -> None:
  ```
- **再試行判定とバックオフ待機フロー**:
  1. レスポンスの `status_code` が `self.retry_http_codes`（デフォルト: `{429, 500, 502, 503, 504}`）に含まれるか検査。
  2. 含まれない場合はそのまま `return response`。
  3. リクエストのメタデータから現在の試行回数 `retries = request.meta.get("retry_times", 0)` を取得。
  4. `retries >= self.max_retry_times` の場合はリトライ上限到達としてそのまま `return response`。
  5. 待機秒数 $T_{\text{wait}}$ の計算:
     - レスポンスヘッダーに `Retry-After` が存在し、整数値または小数値としてパース可能な場合、その値を採用。
     - 存在しない場合は指数バックオフ: $T_{\text{wait}} = \text{self.initial\_delay} \times (\text{self.backoff\_factor}^{\text{retries}})$。
     - $T_{\text{wait}} = \min(T_{\text{wait}}, \text{self.max\_delay})$ で上限クランプ。
  6. `await asyncio.sleep(T_{\text{wait}})` で非同期待機。
  7. `request.meta["retry_times"] = retries + 1` を記録。
  8. `downloader = self.downloader or AsyncHttpDownloader()` によりリクエストを再フェッチ。
  9. 再フェッチ結果のレスポンスに対して再帰的に `process_response` を評価し、最終結果を返却。

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/spider/downloader/middleware.py](../../src/spider/downloader/middleware.py) (`OffsiteMiddleware`, `RetryMiddleware` の実装)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (`_build_spider_middlewares` への登録・ダウンローダー共有)
- [ ] [docs/designs/DSN-06-distributed_spider_and_crawler.md](../designs/DSN-06-distributed_spider_and_crawler.md) (Section 1.1.3, 4.5, 7.3 仕様更新)
- [ ] [tests/spider/test_retry_and_offsite_middlewares.py](../../tests/spider/test_retry_and_offsite_middlewares.py) (新規テストファイル)

---

## 7. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/207-implement-retry-and-offsite-spider-middlewares`

### Step 1: `OffsiteMiddleware` の実装 (`src/spider/downloader/middleware.py`)
1. `_get_domain(url: str)` を活用した正規化ホスト名取得。
2. `is_valid_domain(host: str, allowed_domains: Sequence[str]) -> bool`:
   - 完全一致 (`host == domain`) またはサブドメイン (`host.endswith("." + domain)`) を判定。
3. `process_request(self, request: Request, spider: Any) -> Optional[Response]`:
   - 未許可ドメインの場合に 403 Response (`X-Blocked-By: OffsiteMiddleware`) を返却。

### Step 2: `RetryMiddleware` の実装 (`src/spider/downloader/middleware.py`)
1. `_parse_retry_after(header_val: Optional[str]) -> Optional[float]`:
   - 数値秒数の安全なパース（RFC 9110 準拠）。
2. `process_response(self, request: Request, response: Response, spider: Any) -> Response`:
   - 429/5xx の検知、指数バックオフ計算、`asyncio.sleep`、再フェッチおよび `retry_times` カウント管理。

### Step 3: `runner.py` への統合とダウンローダー共有
1. `_build_spider_middlewares(default_delay: float, enable_cache: bool, downloader: Optional[AsyncHttpDownloader] = None) -> List[Any]`:
   - 最前線に `OffsiteMiddleware()` を配置。
   - `RetryMiddleware(downloader=downloader)` を追加し、同一の接続プール・設定を共有。
2. `run_spider` において作成した `downloader` を `_build_spider_middlewares` に渡すよう更新。

### Step 4: 網羅的ユニットテストスイートの実装 (`tests/spider/test_retry_and_offsite_middlewares.py`)
1. **OffsiteMiddleware テスト**:
   - `allowed_domains=["example.com"]` に対し `https://example.com/foo` および `https://sub.example.com/bar` が通過すること。
   - `https://evil.com/` や `http://127.0.0.1/` が 403 で遮断されること。
   - `allowed_domains` が未定義（`None`）または空リストの場合、全リクエストが通過すること。
2. **RetryMiddleware テスト**:
   - 200 OK のレスポンスがリトライなしでそのまま返ること。
   - 429 受信時に `Retry-After` に従い 1 回リトライして 200 OK に回復すること。
   - 503 受信時に指数バックオフで再試行され、最大 3 回失敗後に 503 レスポンスが返ること（無限ループ防止）。
   - `request.meta["retry_times"]` が正しく 1, 2, 3 と加算されること。
3. **Engine 統合テスト**:
   - Engine 経由で Offsite 遮断および Retry 回復がエンドツーエンドで動作することをモック検証。

### Step 5: 設計書更新 & 品質検証
1. `docs/designs/DSN-06-distributed_spider_and_crawler.md` に Section 4.5 (RetryMiddleware) と Section 7.3 (OffsiteMiddleware) を反映。
2. `make check` (mypy --strict, flake8, radon Grade A, pytest) を全件パス。

---

## 8. 完了条件 / Success Criteria (DoD)

- [x] `OffsiteMiddleware` が `spider.allowed_domains` 外へのリクエストを HTTP 403 で確実に遮断すること。
- [x] `allowed_domains` 未指定時は全ドメインが通過すること（既存 Spider との後方互換性維持）。
- [x] `RetryMiddleware` が HTTP 429, 500, 502, 503, 504 受信時に自動待機・再試行すること。
- [x] `Retry-After` レスポンスヘッダーが正しくパースされ、指数バックオフより優先採用されること。
- [x] `max_retry_times`（デフォルト 3 回）到達時に無限ループせず最終レスポンスを返却すること。
- [x] `runner.py` のミドルウェア連鎖に `OffsiteMiddleware` と `RetryMiddleware` が適切な順序で統合されること。
- [x] `docs/designs/DSN-06-distributed_spider_and_crawler.md` に設計仕様が反映されること。
- [x] 新規ユニットテスト（`tests/spider/test_retry_and_offsite_middlewares.py`）が外部通信ゼロで 100% PASS すること。
- [x] `make check`（静的解析・型チェック・フォーマット・テスト）がエラー 0 件で通過すること。


