# [Issue 058] ゼロ外部依存・大規模分散Webクローラー・スパイダー基盤（DSN-15 準拠）の実装

## 1. 概要 (Overview)
[DSN-15] アーキテクチャ詳細設計に基づき、100% Python 3.14 標準ライブラリのみで動作するゼロ外部依存・大規模分散 Web クローラー・スパイダー基盤（`src/spider/`）を構築する。
非同期 HTTP/1.1 トランスポート、純 Python SPA/Hydration State 抽出エンジン、Prioritized Crawl Frontier、Scalable Bloom Filter、4大ポリシー（Selection, Re-visit, Politeness, Parallelization）、ドメイン固有スパイダー群、および DSN-14 自律分散 DB 連携アイテムパイプラインを実装・検証する。

---

## 2. 背景・目的 (Background & Motivation)
- **サードパーティ完全排除の信頼性**: 外部フレームワーク（Scrapy, Playwright, aiohttp 等）のバージョン互換性やバイナリ依存を排除し、Python 標準ライブラリのみで極限のポータビリティと長期保守性を確保する。
- **超低遅延 SPA 解析**: 重厚な Headless ブラウザを使わず、HTML 内のハイドレーションステート（`__NEXT_DATA__` 等）やインライン JS 内の API エンドポイントを静的解析し、ミリ秒未満で動的 Web ページの構造化データを復元する。
- **自律分散協調**: DSN-14 自律分散 DB エンジンと Consistent Hashing を統合し、線形スケーラビリティとアトミックな Pause/Resume 耐障害性を実現する。

---

## 3. 実装対象コンポーネント (Target Components)

```
src/spider/
├── __init__.py                         # パッケージエクスポート
├── core/                               # 【コアエンジン】
│   ├── __init__.py
│   ├── engine.py                       # 非同期イベント駆動 Engine
│   ├── downloader.py                   # 純Python AsyncHttpDownloader (asyncio.open_connection)
│   ├── scheduler.py                    # 優先度付き Frontier & ドメインスロット
│   ├── selector.py                     # 純Python PureDOMBuilder & CSS セレクタ
│   └── bloom.py                        # 純Python ScalableBloomFilter
├── downloader/                         # 【ダウンロード・レンダリング層】
│   ├── __init__.py
│   ├── spa_handler.py                  # 純Python Hydration State & API Sniffer
│   └── middleware.py                   # UserAgent, Retry, Robots.txt ミドルウェア
├── policies/                           # 【ポリシー制御層】
│   ├── __init__.py
│   ├── autothrottle.py                 # 動的適応遅延 AutoThrottle
│   ├── normalizer.py                   # URL 正規化 & トラップ回避
│   └── opic.py                         # OPIC & フォーカスド・クロール スコアラー
├── spiders/                            # 【ドメイン固有スパイダー】
│   ├── __init__.py
│   ├── base.py                         # BaseSpider 抽象クラス
│   ├── arxiv_spider.py                 # arXiv 多カテゴリ巡回スパイダー
│   ├── iacr_spider.py                  # IACR ePrint 暗号学スパイダー
│   └── advisory_spider.py              # セキュリティアドバイザリ・フィードスパイダー
├── pipeline/                           # 【パイプライン層】
│   ├── __init__.py
│   └── okf_pipeline.py                 # OKF v0.2 変換 & DSN-14 DB 永続化
└── distributed/                        # 【分散・運用層】
    ├── __init__.py
    ├── consistent_hash.py              # Consistent Hash Ring & ドメイン局所ルーティング
    ├── state_storage.py                # Pause / Resume アトミック永続化
    └── contracts.py                    # Spider Contracts 契約駆動テスト
```

---

## 4. 実装タスク・ステップ (Implementation Steps)

1. **Phase 1: マイクロコア & 非同期トランスポート基盤**
   - `src/spider/core/downloader.py`: `asyncio.open_connection`, `ssl.create_default_context`, Keep-Alive 接続プール, Chunked デコード, `zlib` 解凍の実装。
   - `src/spider/core/bloom.py`: `math`, `hashlib`, `bytearray` による純 Python Scalable Bloom Filter の実装。
   - `src/spider/core/selector.py`: `html.parser.HTMLParser` による `DOMNode` ツリー構築 & CSS セレクタエミュレータの実装。
   - `src/spider/core/scheduler.py`: 優先度付きヒープキュー & ドメイン単位ポリテネススロットの実装。
   - `src/spider/core/engine.py`: 非同期データフロー調停 & ライフサイクルシグナルオーケストレーションの実装。

2. **Phase 2: SPA 透過抽出 & ポリシー制御層**
   - `src/spider/downloader/spa_handler.py`: Hydration State JSON 解析（Next.js / Nuxt / Redux）& Reverse API Sniffer の実装。
   - `src/spider/downloader/middleware.py`: Robots.txt, User-Agent, Retry, HttpCache ミドルウェアの実装。
   - `src/spider/policies/autothrottle.py`: EMA レイテンシ追従 AutoThrottle の実装。
   - `src/spider/policies/normalizer.py`: 7段階 URL 正規化 & トラップ回避（深度・循環検知）の実装。
   - `src/spider/policies/opic.py`: OPIC (On-line Page Importance) ＆ トピック適合度スコアリングの実装。

3. **Phase 3: 専門スパイダー & パイプライン層**
   - `src/spider/spiders/base.py`: `BaseSpider` 抽象基底クラス & シード URL 管理。
   - `src/spider/spiders/arxiv_spider.py`, `iacr_spider.py`, `advisory_spider.py`: 各ドメイン専用抽出スパイダー。
   - `src/spider/pipeline/okf_pipeline.py`: Google OKF v0.2 構造化シリアライザ & DSN-14 DB 永続化パイプライン。

4. **Phase 4: 分散協調 & テスト検証**
   - `src/spider/distributed/consistent_hash.py`: ドメイン局所 Consistent Hashing の実装。
   - `src/spider/distributed/state_storage.py`: フロンティア状態の Pause/Resume 永続化。
   - `src/spider/distributed/contracts.py`: Spider Contracts 宣言的テストフレームワーク。
   - `tests/spider/`: 単体・結合・E2E 包括的テストスイートの構築。

---

## 2. 完了定義 (Definition of Done)

- [x] **ゼロ依存 (Zero-Dependency)**: `src/spider/` 配下の全コードが Python 標準ライブラリ (`asyncio`, `html.parser`, `urllib`, `ssl`, `json`, `re`, `hashlib` 等) のみで動作し、サードパーティ依存が 0 件。
- [x] **DSN-15 仕様準拠**:
  - [x] 非同期 I/O ダウンローダー (`AsyncHttpDownloader`)
  - [x] ピュア DOM パーサー & CSS セレクター (`PureDOMParser`, `Selector`)
  - [x] スケーラブル・ブルームフィルター (`ScalableBloomFilter`)
  - [x] ドメイン別ポリテネス・スケジューラー (`Scheduler` with priority heap & rate limiting)
  - [x] SPA ハイドレーション抽出 (`SpaContentExtractor`)
  - [x] クローリングポリシー (`AutoThrottlePolicy`, `UrlNormalizer`, `OpicCalculator`, `TopicRelevanceScorer`)
  - [x] ドメインスパイダー (`ArxivSpider`, `IacrSpider`, `AdvisorySpider`)
  - [x] OKF & DSN-14 DB 出力パイプライン (`OkfItemPipeline`)
  - [x] 分散ルーティング & 状態永続化 (`ConsistentHashRouter`, `StateStorage`, `SpiderContractVerifier`)
- [x] **ユーザーコード & 高度な DSL / デコレータ**:
  - [x] CLI ランナー (`src/spider/runner.py`)
  - [x] Fetcher 統合アダプター (`src/fetcher/ingestion/adapters/spider_adapter.py`)
  - [x] 簡潔な記述が可能な DSL / デコレータ (`SpiderBuilder`, `@spider`, `scrape`)
- [x] **テスト & 品質管理ゲート**:
  - [x] `tests/spider/` テスト 22 件が 100% PASS。
  - [x] `make check_format` および `make static_analysis` (radon, xenon, mypy --strict) が 100% PASS。0 件で通過すること。
- [x] DSN-15 アーキテクチャ設計書および DSN-01 HLD の要件を満たしていること。
