---
ID: 206
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Spider基盤における Response.json プロパティ追加と Spider設定 (download_delay) の伝搬機構実装 (ID: 206)

## 1. 概要 / Summary

[Issue 205](205-implement-cisa-kev-and-nvd-cve-spiders.md)（CISA KEV および NVD CVE Spider の実装）をはじめとする REST API / JSON フィード収集型 Spider の導入に先立ち、クローラー基盤（`src/spider/`）の利便性とレートリミット制御の信頼性を向上させるため、以下の基盤機能を実装する。

1. **`Response.json()` メソッドの追加 (`src/spider/core/downloader.py`)**:
   - `Response` オブジェクトに JSON デコードを安全に行うヘルパーメソッド（`json()`）を追加。各 Spider でのボイラープレートコード（`json.loads(response.text)`）を完全排除する。
2. **Spider 遅延設定（`download_delay` / `custom_settings`）のエンジン層への確実な伝搬**:
   - `BaseSpider` クラスに `download_delay: float = 0.5` および `custom_settings: Dict[str, Any]` 属性を定義。
   - `SpiderRunner` (`src/spider/runner.py`) において、実行対象 Spider の `download_delay` を取得し、`Scheduler(default_delay=...)` および `AutoThrottlePolicy(min_delay=...)` に動的注入する。
   - これにより、NVD のような厳しいレートリミット（APIキー未指定時 6.5 秒以上）が確実にダウンローダー全体に強制され、HTTP 429 エラーや IP バンを根本から防ぐ。
3. **`Request` クエリパラメータ構築ヘルパー (`params`) の追加**:
   - `Request` に `params: Optional[Dict[str, Any]] = None` 引数を追加し、URL クエリ文字列の安全な自動生成（`urllib.parse.urlencode`）と既存クエリとのマージを `__post_init__` でサポート。

---

## 2. トレーサビリティ / Traceability

- 関連 Issue: [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](205-implement-cisa-kev-and-nvd-cve-spiders.md)
- 設計書: [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 対象コンポーネント:
  - `src/spider/core/downloader.py` (`Response`, `Request`)
  - `src/spider/spiders/base.py` (`BaseSpider`)
  - `src/spider/runner.py` (`run_spider`, `SpiderRunner`)
  - `src/spider/core/scheduler.py` (`Scheduler`)
  - `src/spider/policies/autothrottle.py` (`AutoThrottlePolicy`)

---

## 3. 脅威分析・セキュリティ要件 (Threat Modeling & Security)

1. **DoS / レート制限超過 (Rate Limit Exhaustion) の防止**:
   - Spider 定義の `download_delay` を Scheduler および AutoThrottle の双方に漏れなく伝搬させることで、API キー未指定時の高速リクエスト送信による HTTP 429 や IP バンを確実に防止する。
2. **インジェクション / 不正 URL 生成の防止**:
   - クエリパラメータは文字列結合ではなく `urllib.parse.urlencode` により安全にエスケープして URL に結合し、パラメータ汚染や構文破損を防ぐ。
3. **リソース枯渇 / 不正 JSON によるクラッシュの回避**:
   - `Response.json()` 内でパースエラーハンドリングを明確にし、想定外の非 JSON レスポンス受信時にも適切な例外または挙動を提供する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/spider/core/downloader.py](../../src/spider/core/downloader.py) (`Response.json()` メソッドおよび `Request.params` サポート)
- [ ] [src/spider/spiders/base.py](../../src/spider/spiders/base.py) (`BaseSpider` に `download_delay` と `custom_settings` を追加)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (`run_spider` における Spider 設定の `Scheduler` / `AutoThrottlePolicy` への動的注入)
- [ ] [tests/spider/test_downloader_json_and_delay.py](../../tests/spider/test_downloader_json_and_delay.py) (新規: ユニットテスト)

---

## 5. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/206-add-response-json-and-spider-delay-propagation`

### Step 1: `Request.params` および `Response.json()` の実装
- `src/spider/core/downloader.py`:
  - `Request` に `params: Optional[Dict[str, Any]] = None` を追加。
  - `__post_init__` を実装し、`params` が指定されている場合に `urllib.parse.urlsplit` と `urllib.parse.parse_qsl` で既存クエリとマージした上で `urllib.parse.urlencode` し、`self.url` を更新。
  - `Response` に `def json(self) -> Any:` メソッドを追加（`json.loads(self.text)`）。

### Step 2: `BaseSpider` の属性拡張
- `src/spider/spiders/base.py`:
  - `download_delay: float = 0.5`
  - `custom_settings: Dict[str, Any] = {}`

### Step 3: `runner.py` における設定の動的注入
- `src/spider/runner.py`:
  - `run_spider` 内で、インスタンス化した `spider_instance` から `download_delay` を取得。
  - デフォルトの引数 `default_delay`（0.5）よりも Spider 固有の `download_delay` が大きい場合、または明示的に指定された場合に Spider 設定を優先適用。
  - `scheduler = Scheduler(default_delay=effective_delay)`
  - `middlewares = _build_spider_middlewares(effective_delay, enable_cache)`

### Step 4: ユニットテストの作成と品質検証
- `tests/spider/test_downloader_json_and_delay.py`:
  - `Response.json()` の正常系（JSON オブジェクト・配列）と異常系（不正文字列）の検証。
  - `Request` の `params` による URL エンコード（日本語、特殊文字、既存クエリとのマージ）の検証。
  - `run_spider` における `effective_delay` 伝搬の検証。
- `make check` (mypy, flake8, radon, xenon, pytest) のパス確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `Response.json()` により JSON レスポンスが直接取得できること。
- [ ] `Request` に `params={"startIndex": 2000}` を指定した際、正しいクエリ文字列が付加された URL が生成されること。
- [ ] Spider 宣言の `download_delay` が `Scheduler` および `AutoThrottlePolicy` の待機間隔として確実に尊重されること。
- [ ] 新規単体テスト `tests/spider/test_downloader_json_and_delay.py` が全件 PASS すること。
- [ ] `make check` (mypy --strict, flake8, radon, xenon Grade A) がエラー 0 件で通過すること。
