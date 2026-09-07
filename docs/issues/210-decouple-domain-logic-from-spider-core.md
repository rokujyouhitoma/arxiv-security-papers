---
ID: 210
種別: Architecture / Refactor
優先度: High
ステータス: Open (New)
---

# [REFACTOR] src/spider からのドメイン固有実装（セキュリティ/OKF）の完全分離とクローラー純粋基盤化 (ID: 210)

## 1. 概要 / Summary

本システムにおける Web クローラー＆スパイダー基盤（`src/spider/`）は、純粋な汎用クローリング・スクレイピングフレームワーク（ゼロ外部依存・標準ライブラリのみで構成された軽量 Scrapy 相当の基盤）として設計されている。しかし現状、以下の通り「セキュリティ・学術論文・脅威インテリジェンス」という特定ドメイン固有の実装やハードコードされた依存関係が `src/spider/` 内部に混入している：

1. **ドメイン固有パイプラインの混在**: `src/spider/pipeline/okf_pipeline.py` において、Google OKF v0.2（学術論文、脆弱性・CTI、CVSS/CWE、CISA KEV、EPSS）および DSN-14 データベース（`papers`, `vulnerabilities` テーブル）への依存が直接埋め込まれている。
2. **ドメイン固有スパイダーの残存**: `src/spider/spiders/advisory_spider.py` や各種再エクスポートシムが `src/spider/spiders/` に置かれ、クローラー基盤がセキュリティアドバイザリのスキーマを直接知ってしまっている。
3. **ランナー・CLI でのドメイン結合**: `src/spider/runner.py` において、デフォルト出力先が `"outputs/okf_papers"` に固定され、`OkfItemPipeline` がデフォルトパイプラインとして直接インスタンス化されている。

クリーンアーキテクチャおよび関心の分離（Separation of Concerns）を徹底するため、**`src/spider/` にはドメインに依存しない純粋なクローラー基盤（Engine, Scheduler, Downloader, Middlewares, Policies, SPI Registry, 汎用 BaseItemPipeline）のみを保持させ、ドメイン固有（セキュリティ論文・CTI・OKF 出力等）の実装はすべて `src/domain/security/` 配下へ完全移譲・分離**する。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-06 ゼロ外部依存・大規模分散Webクローラー＆スパイダー基盤包括的アーキテクチャ設計書](../designs/DSN-06-distributed_spider_and_crawler.md) (Section 1.1, Section 1.3)
- 設計書: [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 関連 Issue: [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](205-implement-cisa-kev-and-nvd-cve-spiders.md)
- 関連 Issue: [Issue 208: 脆弱性・CTIデータに対応した OKF Item Pipeline の多態化とテンプレート拡張](closed/208-extend-okf-pipeline-for-vulnerability-and-cti-data.md)
- 関連 Issue: [Issue 209: ETag / If-Modified-Since 条件付きリクエストおよび HTTP 304 キャッシュ機構の実装](closed/209-implement-conditional-get-and-etag-caching-for-spiders.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### クローラー基盤側 (`src/spider/` - ドメイン非依存化対象)
- [ ] [src/spider/pipeline/base.py](../../src/spider/pipeline/base.py) (新規: 汎用 `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`)
- [ ] [src/spider/pipeline/okf_pipeline.py](../../src/spider/pipeline/okf_pipeline.py) (ドメイン側 `src/domain/security/pipeline/` へ移動、または後方互換シム化)
- [ ] [src/spider/pipeline/__init__.py](../../src/spider/pipeline/__init__.py) (汎用パイプラインエクスポート)
- [ ] [src/spider/spiders/base.py](../../src/spider/spiders/base.py) (純粋な `BaseSpider` のみ維持)
- [ ] [src/spider/spiders/advisory_spider.py](../../src/spider/spiders/advisory_spider.py) (`src/domain/security/spiders/` へ完全集約)
- [ ] [src/spider/spiders/__init__.py](../../src/spider/spiders/__init__.py) (ドメインスパイダー直接依存の解消)
- [ ] [src/spider/runner.py](../../src/spider/runner.py) (`OkfItemPipeline` のハードコード撤廃、設定可能・DI型パイプライン化、汎用デフォルト出力ディレクトリ化)
- [ ] [src/spider/registry.py](../../src/spider/registry.py) (プラグイン・SPI ベースのスパイダーおよびパイプライン解決)

### ドメイン側 (`src/domain/security/` - 責務集約先)
- [ ] [src/domain/security/pipeline/okf_pipeline.py](../../src/domain/security/pipeline/okf_pipeline.py) (移譲: OKF v0.2 Markdown 生成および DSN-14 DB 永続化)
- [ ] [src/domain/security/spiders/advisory_spider.py](../../src/domain/security/spiders/advisory_spider.py) (アドバイザリスパイダーの実装主体)
- [ ] [src/domain/security/spiders/arxiv_spider.py](../../src/domain/security/spiders/arxiv_spider.py) (学術論文スパイダーの実装主体)
- [ ] [src/domain/security/spiders/iacr_spider.py](../../src/domain/security/spiders/iacr_spider.py) (暗号学論文スパイダーの実装主体)
- [ ] [src/domain/security/plugin.py](../../src/domain/security/plugin.py) (ドメインスパイダー・パイプラインの登録・初期化の明確化)

### テストおよび呼び出し元
- [ ] [tests/spider/](../../tests/spider/) (クローラー基盤の単体テスト: ドメインモデル非依存のダミースパイダー/アイテムで検証)
- [ ] [tests/domain/security/](../../tests/domain/security/) (セキュリティドメインスパイダー・OKF パイプラインの検証)
- [ ] [src/intelligence/cli.py](../../src/intelligence/cli.py) (CLI からのパイプラインおよびスパイダーの呼び出し連携)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/210-decouple-domain-logic-from-spider-core`

1. **汎用 Item Pipeline 抽象の確立 (`src/spider/pipeline/base.py`)**:
   - `BaseItemPipeline`: `async process_item(item: ScrapedItem, spider: Any) -> ScrapedItem`
   - `JsonLinesItemPipeline`: JSONL 形式で任意の `ScrapedItem` をアトミック保存する汎用パイプライン。
   - `ConsoleItemPipeline`: デバッグ・ログ出力用パイプライン。
2. **`OkfItemPipeline` の `src/domain/security/pipeline/` への移設**:
   - `src/domain/security/pipeline/okf_pipeline.py` に `SecurityOkfItemPipeline`（または `OkfItemPipeline`）を移管。
   - `src/spider/pipeline/okf_pipeline.py` は非推奨（Deprecated）警告を発する後方互換リバースプロキシとするか、完全移行。
3. **スパイダー実装の完全ドメイン分離**:
   - `src/spider/spiders/` からドメイン特化スパイダーコードを排除し、`src/domain/security/spiders/` を SSOT（単一の信頼できる情報源）とする。
4. **`src/spider/runner.py` の依存性注入 (DI) 化**:
   - `pipeline_factory` または設定引数により外部からパイプラインを注入可能にする。
   - デフォルトパイプラインをドメイン非依存の `JsonLinesItemPipeline` 等に変更し、セキュリティ用 OKF 出力はドメインプラグインまたは CLI 引数で指定。
5. **Spider / Pipeline Registry の疎結合化**:
   - `SpiderRegistry` がドメインコードを静的インポートせず、プラグインや動的ロード（Entrypoints / Discovery）経由でドメインスパイダーを登録。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/spider/` 配下の全モジュールから `outputs/okf_papers` などのドメイン固有固定パスが撤廃されていること。
- [ ] `src/spider/` が `src/domain/` や特定セキュリティ概念（CVSS, CWE, KEV, EPSS）に一切逆依存していないこと（依存の方向性が `domain -> spider` の単方向であること）。
- [ ] 汎用的な `BaseItemPipeline` および組み込みパイプライン（`JsonLinesItemPipeline` 等）が `src/spider/pipeline/` に整備されていること。
- [ ] セキュリティ論文および CTI（KEV / CVE / Advisory）の OKF Markdown 生成と DB 永続化パイプラインが `src/domain/security/` 配下にカプセル化されていること。
- [ ] `tests/spider/` 配下のテストが特定ドメインに依存せず、基盤フレームワーク単体として完全に独立して PASS すること。
- [ ] 既存の CLI コマンド（`python3 src/intelligence/cli.py spider ...`）およびデータ収集機能が後方互換性を保ち正常動作すること。
- [ ] `make check_format` および `make static_analysis` (mypy --strict, xenon/radon Grade A) が全件 PASS すること。
