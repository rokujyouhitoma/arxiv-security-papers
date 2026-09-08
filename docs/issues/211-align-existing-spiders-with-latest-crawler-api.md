---
ID: 211
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 既存Spider群（AdvisorySpider / ArxivSpider / IacrSpider）の最新クローラーAPI準拠化と基盤改善提案 (ID: 211)

## 1. 概要 / Summary

直近の一連のクローラー基盤強化（Issue 206〜209）において、以下の高度な機能が `src/spider/` に導入された：
1. **Spider 遅延伝搬機構 & `Request.params`** (Issue 206): `download_delay` 宣言によるダウンローダー自動遅延制御、辞書形式パラメータの自動 URL エンコード。
2. **`RetryMiddleware` & `OffsiteMiddleware`** (Issue 207): HTTP 429/503 指数バックオフ、および `allowed_domains` とプライベート/メタデータ IP 遮断による SSRF 防護。
3. **多態的 OKF Item Pipeline** (Issue 208): `ScrapedItem.payload["type"]`（`paper`, `vulnerability`, `security_advisory`）に応じた多態的 Markdown 生成・フロントマター正規化・DB 永続化。
4. **RFC 7232 ETag / If-Modified-Since 条件付きリクエスト & HTTP 304 キャッシュ** (Issue 209): 静的フィード・API の無駄な再取得防止と透過 200 合成。

しかし、初期に実装された既存 Spider 群（`ArxivSpider`, `IacrSpider`, `AdvisorySpider`）はこれらの最新 API 規約に対応しておらず、以下の課題を抱えている：
- `download_delay` 未定義（デフォルト 0.0s となり、arXiv の 3.0s 制限や IACR/MITRE へのマナーを逸脱するリスク）。
- `Request.params` 未使用（URL 文字列内に直接クエリ文字列をハードコード）。
- `payload["type"]` 未明示（`AdvisorySpider` が `type: "paper"` として処理され、OKF 多態的テンプレートの恩恵を受けられない）。
- 重複した XML/Atom/RSS パース処理コード（`_get_elem_text` や ElementTree 名前空間ハンドリングが各 Spider に散在）。

本 Issue では、既存 Spider 群を最新クローラー API へ完全適合させるとともに、横断的な Spider 改修から得られた知見に基づき **`src/spider/` クローラー基盤層自体を改修・高度化すべき改善項目** を整理・提言・実装する。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-06 ゼロ外部依存・大規模分散Webクローラー＆スパイダー基盤包括的アーキテクチャ設計書](../designs/DSN-06-distributed_spider_and_crawler.md)
- 前提完了 Issue: [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](closed/205-implement-cisa-kev-and-nvd-cve-spiders.md)
- 前提完了 Issue: [Issue 206: Spider基盤における Response.json プロパティ追加と Spider設定 (download_delay) の伝搬機構実装](closed/206-add-response-json-and-spider-delay-propagation.md)
- 前提完了 Issue: [Issue 207: Spider基盤における HTTP 429/503 指数バックオフ再試行と SSRF ドメイン防御の実装](closed/207-implement-retry-and-offsite-spider-middlewares.md)
- 前提完了 Issue: [Issue 208: 脆弱性・CTIデータに対応した OKF Item Pipeline の多態化とテンプレート拡張](closed/208-extend-okf-pipeline-for-vulnerability-and-cti-data.md)
- 前提完了 Issue: [Issue 209: ETag / If-Modified-Since 条件付きリクエストおよび HTTP 304 キャッシュ機構の実装](closed/209-implement-conditional-get-and-etag-caching-for-spiders.md)
- 関連アーキテクチャ Issue: [Issue 210: src/spider からのドメイン固有実装（セキュリティ/OKF）の完全分離とクローラー純粋基盤化](210-decouple-domain-logic-from-spider-core.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 既存 Spider の改善対象
- [ ] [src/domain/security/spiders/arxiv_spider.py](../../src/domain/security/spiders/arxiv_spider.py) (`download_delay = 3.0` 設定、`Request.params` 活用、`payload["type"] = "paper"` 明示)
- [ ] [src/domain/security/spiders/iacr_spider.py](../../src/domain/security/spiders/iacr_spider.py) (`download_delay = 3.0` 設定、`payload["type"] = "paper"` 明示、条件付き GET 活用)
- [ ] [src/domain/security/spiders/advisory_spider.py](../../src/domain/security/spiders/advisory_spider.py) (`download_delay = 5.0` 設定、`payload["type"] = "security_advisory"` 明示、CVSS/CVE フィールドの正規化)

### `src/spider/` 基盤層への波及・改善対象
- [ ] [src/spider/core/selector.py](../../src/spider/core/selector.py) (XML/Atom/RSS フィード抽出の軽量共通ヘルパー `FeedSelector` または XML 抽出ユーティリティの追加)
- [ ] [src/spider/spiders/base.py](../../src/spider/spiders/base.py) (`BaseSpider.start_requests()` での `custom_headers` 自動付与および共通プロパティ整理)
- [ ] [src/spider/core/engine.py](../../src/spider/core/engine.py) (ドメイン別 Politeness キューイングまたは遅延制御の柔軟性検証)

### テスト
- [ ] [tests/spider/test_spider_spiders_and_pipeline.py](../../tests/spider/test_spider_spiders_and_pipeline.py) (改修後の Spider パースおよび OKF 多態的出力テストの拡充)
- [ ] [tests/domain/security/test_cve_kev_spiders.py](../../tests/domain/security/test_cve_kev_spiders.py) (ドメイン Spider スイートとの整合性確認)

---

## 4. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/211-align-existing-spiders-with-latest-crawler-api`

### Step 1: 既存 Spider 群の最新 API 準拠化

1. **`ArxivSpider` の改修 (`src/domain/security/spiders/arxiv_spider.py`)**:
   - `download_delay = 3.0`: arXiv 公式 API 規約（1秒に1回を超えない間隔、推奨安全値 3.0s）を宣言。
   - `start_requests()` のオーバーライド:
     `url="https://export.arxiv.org/api/query"` に対して `params={"search_query": "cat:cs.CR", "sortBy": "submittedDate", "sortOrder": "descending", "max_results": 25}` を指定し、Issue 206 で導入された `Request.params` 機能を活用。
   - `payload["type"] = "paper"` を明示付与。
   - `clean_id`, `published_date`, `pdf_url` 等の必須フィールド抽出の堅牢化。

2. **`IacrSpider` の改修 (`src/domain/security/spiders/iacr_spider.py`)**:
   - `download_delay = 3.0`: 暗号学会 ePrint サーバー負荷低減のための Politeness Delay を宣言。
   - `payload["type"] = "paper"` を明示付与。
   - `tags` に `["cryptography", "iacr-eprint"]` を正規化付与。
   - HTTP 304 キャッシュ（`validated_304`）との親和性を担保（静的 RSS フィードの無駄な通信を削減）。

3. **`AdvisorySpider` の改修 (`src/domain/security/spiders/advisory_spider.py`)**:
   - `download_delay = 5.0`: MITRE / CVE フィード取得時の安全マージンを設定。
   - `payload["type"] = "security_advisory"` を明示設定。これにより `OkfItemPipeline` が `type: "security_advisory"` 用のセキュリティ勧告テンプレート（`advisory_id`, `affected_systems`, `remediation` 等）を自動選択して出力。
   - `cve_id` や `title`、参照リンク（`references`）を正規化。

---

### Step 2: 横断的修正から得られた `src/spider/` 基盤層の改善項目（4大提言）

既存 3 種（Arxiv, Iacr, Advisory）および新規 2 種（CisaKev, NvdCve）の計 5 Spider を横断比較・改修することで、以下の基盤層改善ポイントが明確となった：

1. **共通 XML/Atom/RSS フィードパーサーの基盤提供 (`src/spider/core/selector.py`)**:
   - **現状の課題**: `ArxivSpider`, `IacrSpider`, `AdvisorySpider` のいずれも `xml.etree.ElementTree` を直接インポートし、独自に `_get_elem_text` や名前空間辞書 `ns`、例外 try-except を重複実装している。HTML 用には `Selector` があるが、XML フィード用ヘルパーが不足している。
   - **改善案**: `Selector` クラスに XML/Feed 対応メソッド（または軽量な `XmlSelector`）を導入し、名前空間透過な要素テキスト取得 (`find_text("title")`) や XPath/要素リスト展開を 1 行で安全に行えるようにする。

2. **`BaseSpider.start_requests()` における認証ヘッダー / カスタム設定の共通伝搬 (`src/spider/spiders/base.py`)**:
   - **現状の課題**: `NvdCveSpider` などで API キーやヘッダーを付与する際、全 Spider が `start_requests()` を独自に実装して `Request(headers=...)` を構築する必要がある。
   - **改善案**: `BaseSpider` に `custom_headers: Dict[str, str]` 属性を標準定義し、デフォルトの `start_requests()` が自動的に `Request(url=u, headers=dict(self.custom_headers))` を生成するように改善する。

3. **ドメイン単位（Per-Domain）とスパイダー単位（Per-Spider）の Politeness Delay 協調 (`src/spider/core/scheduler.py` / `downloader.py`)**:
   - **現状の課題**: 現在の `download_delay` は Spider インスタンス単位（`spider.download_delay`）でのみ適用される。しかし、1 つの Spider が複数ドメイン（例: `cve.mitre.org` と `nvd.nist.gov`）を巡回する場合、ドメインごとに異なるレート制限（NVD: 6.5s, MITRE: 5.0s）を適用できない。
   - **改善案**: ドメイン別設定辞書 `domain_delays: Dict[str, float]` をサポートするか、ダウンローダーの `AutoThrottle` がレスポンスヘッダーやホスト名単位でドメイン別レートキューを保持できる構造へと発展させる。

4. **`ScrapedItem` の型付きスキーマ検証プロトコル (`src/spider/core/engine.py` または `ItemPipeline`)**:
   - **現状の課題**: `payload` が自由形式辞書 (`Dict[str, Any]`) のため、`type` や `clean_id` のキー名表記揺れ（`cleanId` vs `clean_id` など）がランタイムまで検知できない。
   - **改善案**: `ItemPipeline` 前段に軽量なスキーマチェッカー（または TypedDict / Protocol 定義）を設け、Spider が yield したアイテムの必須属性を早期バリデーション可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `ArxivSpider` に `download_delay = 3.0` が設定され、`Request.params` によるクエリ構築と `payload["type"] = "paper"` が明示されていること。
- [ ] `IacrSpider` に `download_delay = 3.0` が設定され、`payload["type"] = "paper"` が明示されていること。
- [ ] `AdvisorySpider` に `download_delay = 5.0` が設定され、`payload["type"] = "security_advisory"` が明示され、`OkfItemPipeline` からセキュリティ勧告形式 OKF が出力されること。
- [ ] `src/spider/core/selector.py` に XML/Feed 解析の共通ボイラープレートを削減するユーティリティが追加され、各 Spider から利用可能であること。
- [ ] `BaseSpider` のデフォルト `start_requests()` が `custom_headers` を自動伝搬するよう改善されていること。
- [ ] 単体テスト（`tests/spider/` および `tests/domain/security/`）が全件 PASS すること。
- [ ] `make check_format` および `make static_analysis`（mypy --strict, radon/xenon Grade A CC <= 5）を 100% 満たすこと。
