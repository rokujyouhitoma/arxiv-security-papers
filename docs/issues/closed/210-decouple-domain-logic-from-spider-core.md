---
ID: 210
種別: Architecture / Refactor
優先度: High
ステータス: Closed
完了日: 2026-09-09
---

# [REFACTOR] src/spider からのドメイン固有実装（セキュリティ/OKF）の完全分離とクローラー純粋基盤化 (ID: 210)

## 1. 概要 / Summary

本システムにおける Web クローラー＆スパイダー基盤（`src/spider/`）は、純粋な汎用クローリング・スクレイピングフレームワーク（ゼロ外部依存・標準ライブラリのみで構成された軽量 Scrapy 相当の基盤）として設計されている。しかし現状、以下の通り「セキュリティ・学術論文・脅威インテリジェンス」という特定ドメイン固有の実装やハードコードされた依存関係が `src/spider/` 内部に混入している：

1. **ドメイン固有パイプラインの混在**: `src/spider/pipeline/okf_pipeline.py` において、Google OKF v0.2（学術論文、脆弱性・CTI、CVSS/CWE、CISA KEV、EPSS）および DSN-14 データベース（`papers`, `vulnerabilities` テーブル）への依存が直接埋め込まれている。
2. **ドメイン固有スパイダーの残存**: `src/spider/spiders/advisory_spider.py` や各種再エクスポートシムが `src/spider/spiders/` に置かれ、クローラー基盤がセキュリティアドバイザリのスキーマを直接知ってしまっている。
3. **ランナー・CLI でのドメイン結合**: `src/spider/runner.py` において、デフォルト出力先が `"outputs/okf_papers"` に固定され、`OkfItemPipeline` がデフォルトパイプラインとして直接インスタンス化されている。
4. **Registry におけるドメイン逆依存**: `src/spider/registry.py` 内で `from domain import get_domain_registry` を直接呼び出しており、基盤ライブラリが上位ドメインレイヤーに逆依存している。

クリーンアーキテクチャ（Clean Architecture）および関心の分離（Separation of Concerns: SoC）、依存性逆転の原則（Dependency Inversion Principle: DIP）を徹底するため、**`src/spider/` にはドメインに依存しない純粋なクローラー基盤（Engine, Scheduler, Downloader, Middlewares, Policies, SPI Registry, 汎用 BaseItemPipeline）のみを保持させ、ドメイン固有（セキュリティ論文・CTI・OKF 出力等）の実装はすべて `src/domain/security/` 配下へ完全移譲・分離**する。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [DSN-06 ゼロ外部依存・大規模分散Webクローラー＆スパイダー基盤包括的アーキテクチャ設計書](../designs/DSN-06-distributed_spider_and_crawler.md) (Section 1.1, Section 1.3)
  - [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
  - [DSN-05 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md) (Section 20: 責務分離・DIガイドライン)
- **関連 Issue**:
  - [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](closed/205-implement-cisa-kev-and-nvd-cve-spiders.md)
  - [Issue 208: 脆弱性・CTIデータに対応した OKF Item Pipeline の多態化とテンプレート拡張](closed/208-extend-okf-pipeline-for-vulnerability-and-cti-data.md)
  - [Issue 209: ETag / If-Modified-Since 条件付きリクエストおよび HTTP 304 キャッシュ機構の実装](closed/209-implement-conditional-get-and-etag-caching-for-spiders.md)
  - [Issue 211: 既存Spider群（AdvisorySpider / ArxivSpider / IacrSpider）の最新クローラーAPI準拠化と基盤改善提案](211-align-existing-spiders-with-latest-crawler-api.md)
  - [Issue 217: src/database からの具体的データベース指定・ファイルパス結合の完全排除と利用側一元定義（DI）の確立](closed/217-decouple-database-file-definitions-from-database-engine.md)
- **準拠規約**:
  - Clean Architecture / DIP (Dependency Inversion Principle)
  - Google Open Knowledge Format (OKF) v0.2 Specification
  - CWE-22 (Path Traversal 防止), CWE-400 (Uncontrolled Resource Consumption 防止)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### クローラー基盤側 (`src/spider/` - ドメイン非依存化対象)
- [x] [src/spider/pipeline/base.py](../../src/spider/pipeline/base.py) (新規: 汎用 `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `DropItem`, `PipelineRegistry`)
- [x] [src/spider/pipeline/okf_pipeline.py](../../src/spider/pipeline/okf_pipeline.py) (後方互換シム化: `domain.security.pipeline.okf_pipeline` へリバースプロキシ)
- [x] [src/spider/pipeline/__init__.py](../../src/spider/pipeline/__init__.py) (汎用パイプライン基盤のエクスポート)
- [x] [src/spider/spiders/base.py](../../src/spider/spiders/base.py) (純粋な `BaseSpider` のみ維持)
- [x] [src/spider/spiders/__init__.py](../../src/spider/spiders/__init__.py) (静的ドメインスパイダー直接依存の排除、`__getattr__` による遅延非推奨解決)
- [x] [src/spider/runner.py](../../src/spider/runner.py) (`OkfItemPipeline` のハードコード撤廃、設定可能・DI型パイプライン化、汎用デフォルト出力ディレクトリ `"outputs/scraped_data"` への変更)
- [x] [src/spider/registry.py](../../src/spider/registry.py) (ドメイン静的インポートの解消、外部注入型 SPI Discovery コールバックの導入)
- [x] [src/spider/__init__.py](../../src/spider/__init__.py) (ドメイン固有スパイダー・OKF パイプラインの静的エクスポート排除、基盤クラスへの集約)

### ドメイン側 (`src/domain/security/` - 責務集約先)
- [x] [src/domain/security/pipeline/okf_pipeline.py](../../src/domain/security/pipeline/okf_pipeline.py) (移譲・新規配置: OKF v0.2 Markdown 生成および DSN-14 DB 永続化 `SecurityOkfItemPipeline`, `OkfItemPipeline`)
- [x] [src/domain/security/pipeline/__init__.py](../../src/domain/security/pipeline/__init__.py) (ドメインパイプラインのエクスポート)
- [x] [src/domain/security/spiders/advisory_spider.py](../../src/domain/security/spiders/advisory_spider.py) (アドバイザリスパイダーの実装主体)
- [x] [src/domain/security/spiders/arxiv_spider.py](../../src/domain/security/spiders/arxiv_spider.py) (学術論文スパイダーの実装主体)
- [x] [src/domain/security/spiders/iacr_spider.py](../../src/domain/security/spiders/iacr_spider.py) (暗号学論文スパイダーの実装主体)
- [x] [src/domain/security/spiders/cisa_kev_spider.py](../../src/domain/security/spiders/cisa_kev_spider.py) (CISA KEV スパイダーの実装主体)
- [x] [src/domain/security/spiders/nvd_cve_spider.py](../../src/domain/security/spiders/nvd_cve_spider.py) (NVD CVE スパイダーの実装主体)
- [x] [src/domain/security/plugin.py](../../src/domain/security/plugin.py) (ドメインスパイダーに加え、ドメインパイプライン `get_pipelines()` の登録・初期化の明確化)

### テストおよび呼び出し元
- [x] [tests/spider/test_spider_pipelines.py](../../tests/spider/test_spider_pipelines.py) (新規: `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `PipelineRegistry` の単体テスト)
- [x] [tests/spider/test_spider_core.py](../../tests/spider/test_spider_core.py) (クローラー基盤単体テストのドメイン非依存性検証)
- [x] [tests/domain/security/test_okf_pipeline.py](../../tests/domain/security/test_okf_pipeline.py) (セキュリティドメイン OKF パイプラインおよび DSN-14 DB 永続化のテスト移管・拡充)
- [x] [src/intelligence/cli.py](../../src/intelligence/cli.py) (CLI からのパイプラインおよびスパイダーの呼び出し連携確認)

---

## 4. 現状分析とアーキテクチャ課題 (As-Is vs To-Be)

| 評価項目 | 現状 (As-Is) | あるべき姿 (To-Be) | 改善の技術的効果 |
| :--- | :--- | :--- | :--- |
| **Pipeline 抽象と配置** | `src/spider/pipeline/okf_pipeline.py` に OKF v0.2 Markdown 生成、CVSS/CWE、KEV/EPSS、DSN-14 DB が混在。汎用パイプライン抽象が存在しない。 | `src/spider/pipeline/base.py` に `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `PipelineRegistry` を新設。ドメイン OKF パイプラインは `src/domain/security/pipeline/okf_pipeline.py` へ移管。 | クローラー基盤が任意のデータモデル・出力形式（JSONL, RDBMS, カフカ等）に対応可能となり、Scrapy 相当の汎用性を獲得。 |
| **Runner / CLI のパイプライン結合** | `src/spider/runner.py` 内で `OkfItemPipeline` を直接 import し、`output_dir="outputs/okf_papers"` をハードコード。 | `run_spider` および `SpiderRunner` が `pipelines: Optional[Sequence[BaseItemPipeline]] = None` を受け取り DI 化。デフォルトは `JsonLinesItemPipeline(output_dir="outputs/scraped_data")`。 | 他ドメイン（金融・医療・特許等）への再利用時にクローラー基盤側のコード改修が一切不要になる。 |
| **Spider 登録と依存関係** | `src/spider/spiders/__init__.py` で `ArxivSpider`, `AdvisorySpider` などのセキュリティスパイダーを静的 import。`registry.py` が `from domain import get_domain_registry` と上位レイヤーを参照。 | `src/spider/spiders/__init__.py` は `BaseSpider` のみをエクスポート。`SpiderRegistry` は純粋な SPI コンテナとし、外部（プラグイン）からコールバックまたは `register()` 経由で登録。 | 基盤パッケージ `src/spider` からドメインパッケージ `src/domain` への逆依存（循環参照リスク）が完全にゼロとなる。 |
| **後方互換性 (Backward Compatibility)** | 各所（アダプター、既存テスト）が `from spider.pipeline.okf_pipeline import OkfItemPipeline` や `from spider.spiders.arxiv_spider import ArxivSpider` に依存。 | `spider.pipeline.okf_pipeline` および `spider.spiders.*` は `DeprecationWarning` を送出するシムとして維持。 | 既存のスクリプトや外部呼び出し元を破壊することなく段階的マイグレーションを保証。 |
| **テストの関心分離** | `tests/spider/` 内で `OkfItemPipeline` やセキュリティスパイダーを直接テストしており、基盤テストがドメイン変更で壊れる構造。 | `tests/spider/` はドメイン知識を持たないダミースパイダーと汎用パイプラインで基盤機能のみを検証。OKF/セキュリティテストは `tests/domain/security/` に集約。 | テストの実行時間短縮・モック削減・保守性の大幅向上。 |

---

## 5. 脅威分析とセキュリティ要件 (STRIDE Threat Model & Mitigations)

パイプラインの汎用化・外部 DI 化に伴い、以下の脅威ベクトルを分析しセキュリティ対策を講じる。

| 脅威分類 (STRIDE) | 潜在リスク (Threat Vector) | CWE | 対策仕様 (Mitigation Specification) |
| :--- | :--- | :--- | :--- |
| **Tampering / Information Disclosure** | `JsonLinesItemPipeline` や `output_dir` に対する不正なパス指定による Path Traversal | CWE-22 | 出力ディレクトリ・ファイル名生成時に `os.path.abspath` による正規化およびワークスペース内境界検証（`os.path.commonpath` による親ディレクトリ脱出検知）を実施。スパイダー名や clean_id に含まれる不正文字（`../`, `\`, 特殊制御文字）をサニタイズ。 |
| **Denial of Service (DoS)** | 大規模クローリング時の JSON Lines 一括メモリバッファリングによる OOM 障害 | CWE-400 | `JsonLinesItemPipeline` において、全アイテムのインメモリ保持を排除し、アイテム処理ごとにストリーム追記（Line-buffered または定期 flush）するアトミックファイル書き込みを採用。 |
| **Elevation of Privilege / Code Execution** | 不正なクラス名・未検証パイプラインの動的インスタンス化 | CWE-470 | `PipelineRegistry` において、登録可能なパイプラインを `BaseItemPipeline` のサブクラスまたは `process_item` コルーチンを実装したクラスに限定。任意のモジュール動的読み込み時の型チェックを徹底。 |
| **Tampering** | ドロップされたアイテムの不正混入によるパイプライン不整合 | CWE-754 | `DropItem` 例外機構を導入し、不正・破損アイテムがパイプライン連鎖の下流に流れるのを確実に遮断・ロギング。 |

---

## 6. 実装方針 / Implementation Plan

Target Branch: `refactor/210-decouple-domain-logic-from-spider-core`

### Step 1: 汎用 Item Pipeline 抽象基盤の確立 (`src/spider/pipeline/base.py`)
1. `src/spider/pipeline/base.py` を新規作成：
   - `DropItem(Exception)`: パイプライン内で特定のアイテムを破棄するための標準例外クラス。
   - `BaseItemPipeline(ABC)`:
     ```python
     class BaseItemPipeline(ABC):
         async def open_spider(self, spider: Any) -> None:
             pass

         async def close_spider(self, spider: Any) -> None:
             pass

         @abstractmethod
         async def process_item(self, item: ScrapedItem, spider: Any) -> ScrapedItem:
             """Process the item and return it or raise DropItem."""
             return item
     ```
   - `JsonLinesItemPipeline(BaseItemPipeline)`:
     - コンストラクタ: `__init__(self, output_dir: Optional[str] = None, filename_pattern: str = "{spider_name}.jsonl")`
     - 安全なパスサニタイズとディレクトリ自動生成。
     - 各アイテムを JSON 辞書化し、1行1JSON（UTF-8）形式でファイル追記。
   - `ConsoleItemPipeline(BaseItemPipeline)`:
     - アイテムの `item_id`, `title`, `source_url` を標準出力またはロガーへデバッグ出力。
   - `PipelineRegistry`:
     - パイプライン名とパイプラインクラス・ファクトリのレジストリ（`"jsonl"`, `"console"` 等を組み込み登録）。
2. `src/spider/pipeline/__init__.py` から `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `DropItem`, `PipelineRegistry` をエクスポート。

### Step 2: `SecurityOkfItemPipeline` の `src/domain/security/pipeline/` への移譲
1. ディレクトリ `src/domain/security/pipeline/` を新設。
2. `src/domain/security/pipeline/okf_pipeline.py` を作成：
   - `src/spider/pipeline/okf_pipeline.py` の `OkfItemPipeline` 実装全体（Markdown テンプレート構築、CVSS/CWE パース、DSN-14 DB 永続化）を移設。
   - `BaseItemPipeline` を継承。
   - クラス名として `SecurityOkfItemPipeline` を定義し、`OkfItemPipeline = SecurityOkfItemPipeline` のエイリアスを提供。
   - 各種補助関数（`_sanitize_string`, `_sanitize_path_id`, `_format_cvss_meta` 等）も本ファイルに同居。
3. `src/domain/security/pipeline/__init__.py` を作成し、`SecurityOkfItemPipeline`, `OkfItemPipeline` をエクスポート。
4. 元の `src/spider/pipeline/okf_pipeline.py` を後方互換シムに更新：
   ```python
   """Backward-compatibility shim for OkfItemPipeline (Moved to src/domain/security/pipeline/)."""
   import warnings
   from domain.security.pipeline.okf_pipeline import (
       OkfItemPipeline,
       SecurityOkfItemPipeline,
       _sanitize_string,
       _sanitize_path_id,
       _extract_date_folder,
       _format_cvss_meta,
       _score_to_severity,
   )

   warnings.warn(
       "spider.pipeline.okf_pipeline is deprecated; import from domain.security.pipeline.okf_pipeline instead.",
       DeprecationWarning,
       stacklevel=2,
   )
   ```

### Step 3: `src/domain/security/plugin.py` でのパイプライン統合
1. `SecurityPapersDomainPlugin` に `get_pipelines()` メソッドを追加：
   ```python
   def get_pipelines(self) -> Dict[str, Any]:
       from domain.security.pipeline.okf_pipeline import SecurityOkfItemPipeline
       return {"okf": SecurityOkfItemPipeline}
   ```
2. `initialize()` 内で、`PipelineRegistry` に `"okf"` パイプラインを登録。

### Step 4: `src/spider/spiders/` のドメイン依存解消
1. `src/spider/spiders/__init__.py` の静的インポートを解消：
   - `BaseSpider` のみを `__all__ = ["BaseSpider"]` としてエクスポート。
   - 既存の `ArxivSpider`, `IacrSpider`, `AdvisorySpider`, `CisaKevSpider`, `NvdCveSpider` は `__getattr__` を通じた遅延インポートと `DeprecationWarning` の送出により後方互換性を担保。
2. `src/spider/spiders/` 内の個別シムファイル（`advisory_spider.py` 等）にも非推奨警告を追加。

### Step 5: `src/spider/runner.py` の依存性注入 (DI) 化
1. `OkfItemPipeline` への静的依存を撤廃：
   - `run_spider` のシグネチャを拡張：
     ```python
     async def run_spider(
         spider_name: str,
         output_dir: Optional[str] = None,
         max_requests: Optional[int] = None,
         default_delay: float = 0.5,
         enable_cache: bool = True,
         persist_db: bool = False,
         state_file: Optional[str] = None,
         resume_from_state: bool = False,
         pipelines: Optional[Sequence[Any]] = None,
         pipeline_factory: Optional[Callable[..., Sequence[Any]]] = None,
     ) -> List[ScrapedItem]:
     ```
2. パイプライン決定ロジックの改善：
   - 外部から `pipelines` または `pipeline_factory` が与えられた場合はそれを最優先で使用。
   - 指定がない場合：
     - プラグインまたは SPI 経由でスパイダーに対応する推奨パイプラインが登録されているかを検査。
     - セキュリティスパイダー（`arxiv`, `advisory`, `cisa_kev`, `nvd_cve`, `iacr`）でかつ `domain.security` が利用可能な場合は、後方互換性のため動的に `SecurityOkfItemPipeline` を適用。
     - それ以外の場合はドメイン中立な `JsonLinesItemPipeline(output_dir=output_dir or "outputs/scraped_data")` を適用。
3. `SpiderRunner` クラスの改修：
   - `output_dir` のデフォルトを動的解決または汎用化。
   - `run_spider` 呼び出し時に `pipelines` 引数をサポート。
4. CLI 引数（`parse_cli_args`）に `--pipeline` オプション（選択肢: `jsonl`, `okf`, `console`, デフォルト: 自動解決）を追加。

### Step 6: `src/spider/registry.py` および `src/spider/__init__.py` のクリーン化
1. `src/spider/registry.py`:
   - `from domain import get_domain_registry` の静的依存を排斥し、登録リスナーまたは安全な遅延ディスカバリー（Domain プラグイン側の `initialize` 駆動）へ転換。
2. `src/spider/__init__.py`:
   - ドメイン固有の `AdvisorySpider`, `ArxivSpider`, `IacrSpider`, `OkfItemPipeline` の直接エクスポートを非推奨化し、新設した `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `PipelineRegistry` を正式エクスポートに追加。

### Step 7: テストスイートの分離と拡充
1. `tests/spider/test_spider_pipelines.py` を新設：
   - `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline` の独立単体テスト。
   - `DropItem` のフィルタリング動作テスト。
   - `PipelineRegistry` の登録・生成テスト。
2. `tests/domain/security/test_okf_pipeline.py` を新設：
   - `src/domain/security/pipeline/okf_pipeline.py` の OKF v0.2 Markdown 生成および DSN-14 DB 永続化をテスト。
3. 既存の `tests/spider/` および `tests/domain/` 全テストが 100% PASS することを確認。

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] `src/spider/` 配下の全モジュールから `outputs/okf_papers` などのドメイン固有固定パスが撤廃され、汎用パスまたは DI 引数となっていること。
- [x] `src/spider/` が `src/domain/` や特定セキュリティ概念（CVSS, CWE, KEV, EPSS）に静的逆依存していないこと（依存の方向性が `domain -> spider` の単方向であること）。
- [x] 汎用的な `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `PipelineRegistry` が `src/spider/pipeline/base.py` に実装されエクスポートされていること。
- [x] `SecurityOkfItemPipeline`（および `OkfItemPipeline`）が `src/domain/security/pipeline/okf_pipeline.py` に配置され、正常に OKF Markdown 生成と DB 永続化を行えること。
- [x] `src/spider/pipeline/okf_pipeline.py` が後方互換シムとして動作し、既存の import 文を壊さないこと。
- [x] `src/spider/runner.py` において外部からパイプラインを注入可能（DI）であり、CLI から `--pipeline` を指定可能であること。
- [x] `tests/spider/` 配下のテストがドメイン非依存の汎用基盤テストとして独立して実行可能であること。
- [x] 既存の CLI コマンド（`python3 src/intelligence/cli.py spider ...`）および `SpiderSourceAdapter` が後方互換性を保ち正常動作すること。
- [x] `make check_format`（isort, black, flake8）および `make static_analysis`（mypy --strict, xenon Grade A, py_compile）が全件 PASS すること。

---

## 8. 手動検証手順 / Manual Verification Procedure

### 1. 汎用パイプラインとドメインパイプラインの単体テスト実行
```bash
# クローラー基盤およびドメインセキュリティテストの一括実行
PYTHONPATH=.:src .venv/bin/pytest tests/spider/ tests/domain/ -v
```

### 2. 汎用 JsonLinesItemPipeline でのクローラー実行検証
```bash
# 汎用パイプラインでスパイダーを実行し、outputs/scraped_data に JSONL が出力されることを確認
PYTHONPATH=src .venv/bin/python3 -m spider.runner --spider arxiv --pipeline jsonl --max-requests 2 --output-dir outputs/test_scraped_data
ls -la outputs/test_scraped_data/
cat outputs/test_scraped_data/arxiv.jsonl
```

### 3. セキュリティ OKF パイプラインでのクローラー実行検証（後方互換性）
```bash
# ドメイン OKF パイプラインで実行し、outputs/okf_papers に OKF Markdown が生成されることを確認
PYTHONPATH=src .venv/bin/python3 -m spider.runner --spider arxiv --pipeline okf --max-requests 2 --output-dir outputs/test_okf_papers
find outputs/test_okf_papers -name "*.md"
```

### 4. Intelligence CLI 連携検証
```bash
# CLI 経由の spider サブコマンドが正常に完遂することを確認
PYTHONPATH=src .venv/bin/python3 src/intelligence/cli.py spider --spider-name arxiv --depth 2
```

### 5. 静的解析および品質ゲートの通過検証
```bash
make check_format
make static_analysis
```
