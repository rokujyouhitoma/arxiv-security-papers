---
ID: 211
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-09-09
---

# [FEAT] 既存Spider群（AdvisorySpider / ArxivSpider / IacrSpider）の最新クローラーAPI準拠化と基盤改善提案 (ID: 211)

## 1. 概要 / Summary

直近の一連のクローラー基盤強化（Issue 206〜210）において、`src/spider/` に以下の先進的なクローリング機能およびドメイン分離アーキテクチャが確立された：

1. **Spider 遅延伝搬機構 & `Request.params`** (Issue 206): `download_delay` 宣言によるダウンローダー自動遅延制御、および辞書形式パラメータの自動 URL クエリエンコード。
2. **`RetryMiddleware` & `OffsiteMiddleware`** (Issue 207): HTTP 429/503 指数バックオフ再試行、および `allowed_domains` とプライベート/クラウドメタデータ IP 遮断による SSRF 防護。
3. **多態的 OKF Item Pipeline** (Issue 208): `ScrapedItem.payload["type"]`（`security-paper`, `vulnerability`, `security_advisory`）に応じた多態的 Markdown 生成・フロントマター正規化・DB 永続化。
4. **RFC 7232 ETag / If-Modified-Since 条件付きリクエスト & HTTP 304 キャッシュ** (Issue 209): 静的フィード・API の無駄な再取得防止と透過 200 合成。
5. **ドメインロジックの完全分離とクローラー純粋基盤化** (Issue 210): `BaseItemPipeline`, `JsonLinesItemPipeline`, `ConsoleItemPipeline`, `PipelineRegistry` による純粋なクローラーフレームワーク化と、`src/domain/security/pipeline/okf_pipeline.py` へのドメイン責務集約。

しかし、初期に実装された既存 Spider 群（`ArxivSpider`, `IacrSpider`, `AdvisorySpider`）はこれらの最新 API 規約に対応しておらず、以下の技術的負債・課題を抱えている：

- **遅延制御の欠如**: `download_delay` が未定義（デフォルト値 0.5s または 0.0s）のため、arXiv API 規約（推奨 3.0s）や IACR ePrint / MITRE CVE サーバーへのアクセス負荷（Politeness）を逸脱するリスクが存在する。
- **URL パラメータのハードコード**: `Request.params` を活用せず、URL 文字列内に直接クエリパラメータ（`cat:cs.CR&sortBy=...` 等）を連結しており、エンコーディング不備や拡張性低下の原因となっている。
- **アイテム種別（`payload["type"]`）の未明示**: `AdvisorySpider` が `payload["type"]` を付与しておらず、デフォルトの `security-paper` として処理され、OKF 多態的セキュリティ勧告テンプレート（CVE, CVSS, 影響製品, 緩和策テーブル）の恩恵を受けられていない。
- **XML/Atom/RSS パースコードの重複散在**: `ArxivSpider`, `IacrSpider`, `AdvisorySpider` のすべてが `xml.etree.ElementTree` を個別にインポートし、独自に名前空間定義やテキスト抽出ヘルパー（`_get_elem_text` など）を重複実装しており、保守性および XXE 防御の観点で統一性に欠ける。
- **基盤層におけるカスタムヘッダー自動伝搬の不足**: `BaseSpider.start_requests()` が標準提供されておらず、各 Spider が独自の `start_urls` ループに依存している。

本 Issue では、**既存 Spider 3 種を最新クローラー API へ完全適合** させるとともに、共通課題の抽出から得られた知見に基づき **`src/spider/` クローラー基盤層自体に軽量な XML/Feed 抽出ユーティリティ（`XmlSelector`）および `BaseSpider.start_requests()` 共通伝搬機構を導入・高度化** する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-06 ゼロ外部依存・大規模分散Webクローラー＆スパイダー基盤包括的アーキテクチャ設計書](../designs/DSN-06-distributed_spider_and_crawler.md) (Section 1.1, Section 3.2)
  - [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
  - [DSN-05 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md) (Section 20: 責務分離・DIガイドライン)
- **前提・関連 Issue**:
  - [Issue 205: CISA KEV および NVD CVE 向け Pure-Python Spider の実装とクローラー基盤への統合](closed/205-implement-cisa-kev-and-nvd-cve-spiders.md)
  - [Issue 206: Spider基盤における Response.json プロパティ追加と Spider設定 (download_delay) の伝搬機構実装](closed/206-add-response-json-and-spider-delay-propagation.md)
  - [Issue 207: Spider基盤における HTTP 429/503 指数バックオフ再試行と SSRF ドメイン防御の実装](closed/207-implement-retry-and-offsite-spider-middlewares.md)
  - [Issue 208: 脆弱性・CTIデータに対応した OKF Item Pipeline の多態化とテンプレート拡張](closed/208-extend-okf-pipeline-for-vulnerability-and-cti-data.md)
  - [Issue 209: ETag / If-Modified-Since 条件付きリクエストおよび HTTP 304 キャッシュ機構の実装](closed/209-implement-conditional-get-and-etag-caching-for-spiders.md)
  - [Issue 210: src/spider からのドメイン固有実装（セキュリティ/OKF）の完全分離とクローラー純粋基盤化](closed/210-decouple-domain-logic-from-spider-core.md)
- **準拠規約・標準**:
  - RFC 7232 (Conditional Requests) / RFC 4287 (Atom Syndication Format) / RSS 2.0 Specification
  - Google Open Knowledge Format (OKF) v0.2 Specification
  - arXiv API User Manual (Politeness Rule: 1 request per 3 seconds)
  - MITRE CVE / IACR ePrint Crawling Policy

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### クローラー基盤側 (`src/spider/` - 共通基盤機能拡張)
- [x] [src/spider/core/selector.py](../../src/spider/core/selector.py) (新規: `XmlNode`, `XmlSelector` の実装。名前空間透過な要素検索 `find_text`, `find_all`, `get_attr` および XXE 防御ユーティリティの追加)
- [x] [src/spider/spiders/base.py](../../src/spider/spiders/base.py) (`BaseSpider.start_requests()` メソッドの標準化、`custom_headers: Dict[str, str]` 属性の追加と自動伝搬)
- [x] [src/spider/core/engine.py](../../src/spider/core/engine.py) (`_enqueue_start_urls` において `spider.start_requests()` を優先呼び出し、未定義時のみ `start_urls` にフォールバックする協調制御の導入)
- [x] [src/spider/__init__.py](../../src/spider/__init__.py) (`XmlSelector`, `XmlNode` の正式エクスポート追加)

### ドメイン側 (`src/domain/security/` - 既存 Spider 最新化 & 多態性保証)
- [x] [src/domain/security/spiders/arxiv_spider.py](../../src/domain/security/spiders/arxiv_spider.py) (`download_delay = 3.0` 設定、`start_requests()` による `Request.params` 活用、`payload["type"] = "security-paper"` 明示、`XmlSelector` による Atom パースのボイラープレート撤廃)
- [x] [src/domain/security/spiders/iacr_spider.py](../../src/domain/security/spiders/iacr_spider.py) (`download_delay = 3.0` 設定、`payload["type"] = "security-paper"` 明示、`tags = ["cryptography", "iacr-eprint"]` 正規化、`XmlSelector` による RSS パースの共通化)
- [x] [src/domain/security/spiders/advisory_spider.py](../../src/domain/security/spiders/advisory_spider.py) (`download_delay = 5.0` 設定、`payload["type"] = "security_advisory"` 明示、CVE-ID / 影響製品 / 緩和策の構造化抽出、`XmlSelector` への刷新)
- [x] [src/domain/security/pipeline/okf_pipeline.py](../../src/domain/security/pipeline/okf_pipeline.py) (`payload["type"]` における `"security_advisory"`（アンダースコア）および `"security-advisory"`（ハイフン）の双方を完全等価にハンドリングする多態的ディスパッチの堅牢化)

### テストスイート
- [x] [tests/spider/test_spider_core.py](../../tests/spider/test_spider_core.py) (`XmlSelector` の名前空間透過パース、属性抽出、XXE 防御の単体テスト追加)
- [x] [tests/spider/test_spider_spiders_and_pipeline.py](../../tests/spider/test_spider_spiders_and_pipeline.py) (`ArxivSpider`, `IacrSpider`, `AdvisorySpider` の `download_delay`、`start_requests()`、`payload["type"]`、OKF 出力の最新化テスト)
- [x] [tests/domain/security/test_cve_kev_spiders.py](../../tests/domain/security/test_cve_kev_spiders.py) (ドメイン全体スパイダー群との結合・回帰テスト)

---

## 4. セキュリティ脅威分析と多層防御設計 (Threat Modeling & Security Mitigations)

| 脅威分類 (STRIDE / CWE) | 潜在的リスク | 本 Issue における対策・多層防御 |
| :--- | :--- | :--- |
| **CWE-611 / CWE-776 (XXE / XML Entity Expansion)** | 悪意ある外部 XML フィード（Billion Laughs 攻撃や外部 DTD 参照）による DoS または機密ファイル漏洩 | `XmlSelector` において `xml.etree.ElementTree.XMLParser` を安全に初期化し、エンティティ展開や外部 DTD のロードを無効化。巨大 XML ペイロードのサイズ制限（上限 10MB）を適用。 |
| **CWE-918 (SSRF / 不正オリジン通信)** | フィード内の `<link>` や `<id>` から抽出した不正 URL への HTTP リクエストによる内部網探索 | `OffsiteMiddleware` により `allowed_domains` への強制制限およびプライベート IP（10.0.0.0/8, 127.0.0.0/8, 169.254.169.254）の自動遮断を徹底。 |
| **CWE-400 (過剰なリクエスト頻度による DoS/アクセス遮断)** | クローラーの過剰アクセスによる外部 API（arXiv / IACR / MITRE）からの IP バン（HTTP 429） | `download_delay` を明示宣言（arXiv: 3.0s, IACR: 3.0s, MITRE: 5.0s）。`AutoThrottlePolicy` および `RetryMiddleware` との協調により、相手先サーバーの負荷を最小化。 |
| **CWE-1333 (ReDoS / 正規表現破綻)** | CVE-ID や日付抽出時の脆弱な正規表現による CPU 枯渇 | 単純かつ決定論的な正規表現（`r"CVE-\d{4}-\d{4,7}"`）に限定し、バックトラッキングが発生しないアトミックパターンを使用。 |
| **CWE-22 (Path Traversal)** | `clean_id` に `../` や不正文字が含まれることによるファイルシステム破壊 | OKF Pipeline の `_sanitize_path_id()` により、ベースネーム抽出および記号サニタイズ（`[a-zA-Z0-9_\-\.]`）を厳格適用。 |

---

## 5. 詳細実装方針とアーキテクチャ設計 / Implementation Plan

Target Branch: `feat/211-align-existing-spiders-with-latest-crawler-api`

### Step 1: `src/spider/core/selector.py` への `XmlSelector` / `XmlNode` の新設

HTML 解析用の `Selector(HTMLParser)` に加え、Atom/RSS/XML データを純粋標準ライブラリのみで高速・安全に解析する `XmlNode` および `XmlSelector` を新設する。

```python
# src/spider/core/selector.py プロトタイプ
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional

class XmlNode:
    """Represents an XML element node with namespace-agnostic querying."""
    def __init__(self, elem: ET.Element) -> None:
        self._elem = elem

    @property
    def tag(self) -> str:
        # {http://www.w3.org/2005/Atom}entry -> entry
        return self._elem.tag.split("}")[-1] if "}" in self._elem.tag else self._elem.tag

    @property
    def text(self) -> str:
        return (self._elem.text or "").strip()

    def get_attr(self, name: str, default: str = "") -> str:
        return self._elem.attrib.get(name, default)

    def find_text(self, tag_name: str, default: str = "") -> str:
        """Finds first direct or nested child matching local tag name, returning stripped text."""
        ...

    def find_all(self, tag_name: str) -> List[XmlNode]:
        """Finds all direct or nested children matching local tag name."""
        ...

class XmlSelector:
    """Namespace-agnostic, memory-safe XML / Feed document selector."""
    def __init__(self, text: str) -> None:
        self.root: Optional[XmlNode] = self._parse(text)

    def _parse(self, text: str) -> Optional[XmlNode]:
        # XXE-safe parsing with size guard
        if len(text) > 10 * 1024 * 1024:
            raise ValueError("XML payload exceeds 10MB limit")
        try:
            elem = ET.fromstring(text)
            return XmlNode(elem)
        except Exception:
            return None

    def find_all(self, tag_name: str) -> List[XmlNode]:
        return self.root.find_all(tag_name) if self.root else []
```

### Step 2: `src/spider/spiders/base.py` & `engine.py` の協調機能強化

1. **`src/spider/spiders/base.py`**:
   - `custom_headers: Dict[str, str] = {}` をクラス属性およびインスタンス属性として初期化。
   - `start_requests()` メソッドを定義し、デフォルトで `start_urls` から `Request(url=u, headers=dict(self.custom_headers))` を生成・yield。
   - `download_delay: float = 0.5` をデフォルトとして維持。

2. **`src/spider/core/engine.py`**:
   - `_enqueue_start_urls` を更新し、スパイダーが `start_requests()` メソッドを実装している場合はそれを直接反復してスケジュール。未実装またはジェネレータが空の場合は従来の `start_urls` をキューイング。

### Step 3: `ArxivSpider` の最新 API 準拠化 (`src/domain/security/spiders/arxiv_spider.py`)

1. **遅延制御**: `download_delay: float = 3.0` を明示（arXiv 公式 API ガイドライン準拠）。
2. **`start_requests()` 実装**:
   ```python
   def start_requests(self) -> Iterator[Request]:
       yield Request(
           url="https://export.arxiv.org/api/query",
           params={
               "search_query": "cat:cs.CR",
               "sortBy": "submittedDate",
               "sortOrder": "descending",
               "max_results": "25",
           },
           callback="parse",
       )
       yield Request(url="https://arxiv.org/list/cs.CR/recent", callback="parse")
   ```
3. **`payload["type"] = "security-paper"`**: 明示的に型タグを付与し、OKF 変換エンジンが論文テンプレート（著者リスト、抄録、PDF URL）を適用できるようにする。
4. **`XmlSelector` の適用**: `_parse_atom_feed` を `XmlSelector` を用いてシンプルに書き換え、名前空間辞書の冗長な引き回しを排除。

### Step 4: `IacrSpider` の最新 API 準拠化 (`src/domain/security/spiders/iacr_spider.py`)

1. **遅延制御**: `download_delay: float = 3.0` を明示（ePrint サーバーへの負荷軽減）。
2. **アイテム種別 & タグ**:
   - `payload["type"] = "security-paper"` を付与。
   - `tags = ["cryptography", "zero-knowledge", "iacr-eprint"]` を正規化。
3. **`XmlSelector` の適用**: `_map_iacr_item` を `XmlSelector` 経由に統一し、`<item>` 内の `<title>`, `<link>`, `<description>`, `<pubDate>` を 1 行で安全抽出。

### Step 5: `AdvisorySpider` の最新 API 準拠化 (`src/domain/security/spiders/advisory_spider.py`)

1. **遅延制御**: `download_delay: float = 5.0` を明示（MITRE ダウンロードサーバー負荷軽減）。
2. **アイテム種別 & 脆弱性メタデータ**:
   - `payload["type"] = "security_advisory"` を付与。
   - `cve_id`（`CVE-YYYY-NNNN`）をタイトル・説明文から安全抽出。
   - `source = "cve-mitre"` を設定。
   - `references` に一次情報リンク（`item.find_text("link")`）を配列で格納。
3. **OKF パイプライン多態性連携 (`src/domain/security/pipeline/okf_pipeline.py`)**:
   - `_build_okf_markdown` において `item_type in ("vulnerability", "security-advisory", "security_advisory")` をサポートし、脆弱性・セキュリティ勧告用 OKF v0.2 Markdown を出力。
   - `_persist_to_dsn14_db` において `vulnerabilities` テーブルへアトミック INSERT。

### Step 6: テストスイートの拡充と品質ゲート検証

1. **`tests/spider/test_spider_core.py`**:
   - `XmlSelector` による整形式 XML、名前空間付き XML（Atom）、不正 XML のエラーハンドリングテスト。
   - `BaseSpider.start_requests()` でのカスタムヘッダー自動付与テスト。
2. **`tests/spider/test_spider_spiders_and_pipeline.py`**:
   - `ArxivSpider`, `IacrSpider`, `AdvisorySpider` の `download_delay`、`start_requests` の `params`、`payload["type"]`、OKF 多態的出力のアサーション。
3. **全自動品質ゲートの実行**:
   - `make check_format` (isort, black, flake8)
   - `make static_analysis` (xenon Grade A, mypy --strict, py_compile)
   - `pytest` 全件 PASS

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/spider/core/selector.py` に `XmlNode` および `XmlSelector` が実装され、名前空間透過なタグ検索（`find_text`, `find_all`）と XXE 防御が担保されていること。
- [x] `src/spider/spiders/base.py` の `BaseSpider` に `custom_headers` が追加され、デフォルトの `start_requests()` がヘッダーを自動伝搬すること。
- [x] `src/spider/core/engine.py` の `_enqueue_start_urls` が `spider.start_requests()` を最優先でスケジュールすること。
- [x] `ArxivSpider` に `download_delay = 3.0` が設定され、`Request.params` を用いた `start_requests()` が実装され、`payload["type"] = "security-paper"` が明示されていること。
- [x] `IacrSpider` に `download_delay = 3.0` が設定され、`payload["type"] = "security-paper"` が明示され、`XmlSelector` を用いてパースされていること。
- [x] `AdvisorySpider` に `download_delay = 5.0` が設定され、`payload["type"] = "security_advisory"` が明示され、多態的 OKF Pipeline から脆弱性・勧告形式 OKF が出力されること。
- [x] `src/domain/security/pipeline/okf_pipeline.py` が `security_advisory`（アンダースコア表記）を認識し、適切なフロントマターと DB 永続化を行うこと。
- [x] `tests/spider/` および `tests/domain/` の全テスト（既存および新規）が 100% PASS すること。
- [x] `make check_format` および `make static_analysis`（mypy --strict, xenon Grade A CC <= 5）が警告・エラー 0 件で通過すること。

---

## 7. 手動検証手順 / Manual Verification Procedure

### 1. 新設 XML セレクターおよびスパイダーの単体テスト実行
```bash
PYTHONPATH=.:src .venv/bin/pytest tests/spider/test_spider_spiders_and_pipeline.py tests/spider/test_spider_core.py -v
```

### 2. ArxivSpider の Request.params および遅延伝搬の検証
```bash
# ArxivSpider を実行し、params 経由でクエリが正常に送出され、download_delay=3.0 が適用されることを確認
PYTHONPATH=src .venv/bin/python3 -m spider.runner --spider arxiv --pipeline jsonl --max-requests 2 --output-dir outputs/test_scraped_data
cat outputs/test_scraped_data/arxiv_spider.jsonl | head -n 1
```

### 3. AdvisorySpider の security_advisory 多態的 OKF 出力検証
```bash
# AdvisorySpider の出力が OKF パイプラインによって security_advisory 形式で生成されることを確認
PYTHONPATH=src .venv/bin/python3 -m spider.runner --spider advisory --pipeline okf --max-requests 1 --output-dir outputs/test_okf_advisories
find outputs/test_okf_advisories -name "*.md" | xargs head -n 25
```

### 4. 品質ゲート一括検証
```bash
make check_format
make static_analysis
```
