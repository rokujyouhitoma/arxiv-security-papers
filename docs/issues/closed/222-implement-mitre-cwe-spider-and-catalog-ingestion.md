---
ID: 222
種別: Feature
優先度: High
ステータス: Closed
担当エージェント: Information Security Specialist / Systems Architect / Database Specialist / Network Specialist / Software Development (SWD)
---

# [FEAT/CTI] MITRE CWE 公式カタログ自動インジェスト用 CweSpider の実装と DB / オントロジー連携基盤の確立 (ID: 222)

## 1. 概要 / Summary

サイバーセキュリティ学術論文分析（`arxiv-security-papers`）において、論文（Paper）と根本原因である弱点分類（CWE: Common Weakness Enumeration）との関係は、論文が個別具体的な脆弱性実例（CVE）やエクスプロイト実証を取り扱う場合が多く、因果グラフ上で「Paper ➔ CVE ➔ CWE」と 2 ホップ離れるケースが存在する。
しかしながら、**脆弱性に関する構造分析・根本原因分析・防御策（Mitigation）の観点においては、CWE は「1ホップ（CVE ➔ CWE）」または「脆弱性の本質そのもの」** であり、脅威モデリング、自動パッチ合成、およびセキュアコーディング指導において極めて決定的な重要性を持つ。

現在、本リポジトリでは NVD CVE スパイダー（`NvdCveSpider`）が収集する CVE レコード内の `weaknesses` 配列から CWE-ID を抽出するか、`src/domain/security/taxonomy/cwe.py` に代表的な弱点定義（CWE-89, CWE-79 等の主要弱点）を静的辞書 `CWE_DEFENSE_MAP` として保持しているのみにとどまっている。

本 Issue では、MITRE 公式データソース（REST API `cwe-api.mitre.org` および公式ダウンロードデータ）から **CWE 全カタログ（約 1,000 種類以上の弱点ツリー、抽象度区分、親子関係、プラットフォーム、緩和策）および CWE Top 25** を自動取得・インジェストする専用スパイダー `CweSpider` を `src/domain/security/spiders/cwe_spider.py` に実装し、純粋 Python 自作データベース（`cti_catalog_db`）および W3C セキュリティ知識オントロジーナレッジグラフへ永続化・定期更新する基盤を確立する。

あわせて、関連するアーキテクチャ設計仕様書（`DSN-06` 分散スパイダー基盤設計書、`DSN-20` 外部セキュリティ知識統合インジェスト基盤設計書）を最新の実態に合わせて改訂・同期する。

```mermaid
flowchart TD
    subgraph Upstream ["🌐 MITRE CWE 公式データソース"]
        MITRE_API["CWE REST API (cwe-api.mitre.org)"]
        MITRE_DATA["CWE Official Downloads (cwec_v4.x)"]
    end

    subgraph Spider_Subsystem ["🕷️ クローラー・スパイダー基盤 (src/spider/ & src/domain/)"]
        CweSpider["CweSpider (src/domain/security/spiders/cwe_spider.py)<br/>• 弱点メタデータ・階層ツリー抽出<br/>• Top 25 ランク・抽象度 (Class/Base/Variant)<br/>• 緩和策 (Mitigations)・検出手法抽出"]
        Registry["SpiderRegistry & SecurityPlugin<br/>• src/domain/security/plugin.py<br/>• --spider cwe_spider で CLI 実行"]
        Middleware["Downloader Middleware<br/>• ETag / 304 キャッシュ<br/>• 5.0s Politeness 遅延制御<br/>• Decompression Bomb 防御"]
    end

    subgraph Storage_Layer ["💾 永続化ストレージ (cti_catalog_db)"]
        CTI_Storage["CTICatalogStorage (src/domain/security/cti/storage.py)<br/>• cti_cwes テーブル (weakness_id, name, abstraction, top25_rank)<br/>• cti_cwe_relationships テーブル (parent/child, capec_id)<br/>• FTS5 全文検索インデックス"]
    end

    subgraph Knowledge_and_Ontology ["🧠 オントロジー ＆ 因果グラフ連携"]
        HybridTaxonomy["ハイブリッド CWE タクソノミー (taxonomy/cwe.py)<br/>• 静的 Semgrep ルール + 動的 cti_cwes カタログ"]
        GraphEngine["Property Graph DB (src/graph/)<br/>• Weakness ノード (cwe:CWE-XXX)<br/>• 因果エッジ (CVE -[affectsWeakness]-> CWE)"]
    end

    subgraph Causality_Analysis ["🎯 因果ホップ構造の最適化"]
        Paper["学術論文 (Paper)"]
        CVE["脆弱性実例 (CVE: 1ホップ)"]
        CWE_Entity["弱点根本原因 (CWE: 2ホップ / 脆弱性本質)"]
        Paper -->|学術的実証 (2ホップ)| CWE_Entity
        Paper -->|事例対象 (1ホップ)| CVE
        CVE -->|根本原因 (1ホップ / 直結)| CWE_Entity
    end

    MITRE_API --> CweSpider
    MITRE_DATA --> CweSpider
    CweSpider --> Middleware
    Middleware --> Registry
    CweSpider --> CTI_Storage
    CTI_Storage --> HybridTaxonomy
    CTI_Storage --> GraphEngine
```

---

## 2. トレーサビリティ / Traceability

- **外部公式仕様・データソース**:
  - MITRE CWE (Common Weakness Enumeration) 公式ポータル: `https://cwe.mitre.org/`
  - MITRE CWE 公式 REST API 仕様: `https://cwe-api.mitre.org/`
  - MITRE CWE カタログダウンロード: `https://cwe.mitre.org/data/downloads.html`
  - MITRE CWE Top 25 Most Dangerous Software Weaknesses
- **リポジトリ内設計仕様書 (DSN)**:
  - `docs/designs/DSN-06-distributed_spider_and_crawler.md` (分散スパイダー＆クローラー包括設計書 - ドメインスパイダー連携)
  - `docs/designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md` (外部セキュリティ知識統合インジェスト・ローカルカタログ管理基盤設計仕様書)
  - `docs/designs/DSN-17-security_knowledge_ontology.md` (セキュリティ知識オントロジー設計書 - Weakness エンティティ)
  - `docs/designs/DSN-24-unified_management_cli_and_interactive_dbshell.md` (`manage.py` DSN-24 スキーマ整合)
- **関連 Issue**:
  - [Issue 205](closed/205-implement-cisa-kev-and-nvd-cve-spiders.md) (CISA KEV および NVD CVE Spider の実装)
  - [Issue 208](closed/208-extend-okf-pipeline-for-vulnerability-and-cti-data.md) (CTI データに対応した OKF Item Pipeline の多態化)
  - [Issue 210](closed/210-decouple-domain-logic-from-spider-core.md) (src/spider からのドメイン固有実装分離)
  - [Issue 218](closed/218-migrate-cti-catalog-and-analytics-db-to-pure-database-engine.md) (cti_catalog.db の独自データベース移行)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 1. スパイダー実装 ＆ プラグイン登録
- [x] [NEW] `src/domain/security/spiders/cwe_spider.py`: MITRE CWE 公式 API / データ取得用 Pure-Python スパイダー本体
- [x] [NEW] `src/spider/spiders/cwe_spider.py`: スパイダー基盤用後方互換シンボリック再エクスポート
- [x] [MODIFY] `src/domain/security/plugin.py`: `SecurityPapersDomainPlugin.get_spiders()` への `cwe_spider` 登録
- [x] [MODIFY] `src/spider/spiders/__init__.py`: `CweSpider` のエクスポート定義

### 2. データ永続化・ストレージ層 (`cti_catalog_db`)
- [x] [MODIFY] `src/domain/security/cti/storage.py`:
  - `cti_cwes` テーブル DDL 定義 (`cwe_id`, `name`, `abstraction`, `description`, `top25_rank`, `is_top25`, `status`, `extended_meta`)
  - `cti_cwe_relationships` テーブル DDL 定義 (`source_cwe_id`, `target_cwe_id`, `relation_type`)
  - `insert_cwe()`, `bulk_insert_cwes()`, `get_cwe()`, `search_cwes()` メソッドの実装
- [x] [MODIFY] `src/settings.py`: `cti_catalog_db.TABLES` への `cti_cwes`, `cti_cwe_relationships` 登録

### 3. タクソノミー ＆ オントロジー連携
- [x] [MODIFY] `src/domain/security/taxonomy/cwe.py`: 静的 `CWE_DEFENSE_MAP` と `cti_catalog_db` をシームレスに結合するハイブリッド参照関数（`get_cwe_definition(cwe_id)`）の実装

### 4. 設計書改訂
- [x] [MODIFY] `docs/designs/DSN-06-distributed_spider_and_crawler.md`: CWE スパイダーの仕様、URL 境界防御、Politeness 制御の追記
- [x] [MODIFY] `docs/designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md`: CWE プロバイダ、`cti_cwes` スキーマ、2ホップ/1ホップ因果関係の反映

### 5. 台帳・テスト
- [x] [MODIFY] `docs/issues/README.md`: Issue 222 ステータスを `Closed` に更新
- [x] [NEW] `tests/domain/security/spiders/test_cwe_spider.py`: CWE スパイダーのパース・契約・データマッピング単体テスト
- [x] [NEW] `tests/domain/security/cti/test_cwe_storage.py`: CWE ストレージ CRUD およびリレーション探索テスト

---

## 4. 脅威モデル分析 ＆ セキュリティガードレール (Threat Model & Mitigations)

1. **SSRF / 不正ドメインアクセス防御**:
   - `allowed_domains`: `{"cwe.mitre.org", "cwe-api.mitre.org"}` を厳格に強制。外部リダイレクト追従時もホワイトリスト外へのアクセスを遮断。
2. **Decompression Bomb / リソース枯渇防御**:
   - MITRE 提供のアーカイブや大量 JSON レスポンスを展開する際、最大展開サイズ（50MB 上限）を設け、メモリ枯渇攻撃を防止。
3. **HTTP レート制限 ＆ 礼儀正しいクロール (Politeness)**:
   - `download_delay: 5.0` 秒をデフォルト設定。
   - ETag / If-Modified-Since による HTTP 304 キャッシュ連携を行い、同一バージョン取得時の不要な上流トラフィックをゼロ化。
4. **SQL インジェクション防御**:
   - `cti_catalog_db` への登録は、`storage.py` のプレースホルダーパラメータ化クエリ（`?` バインド）を厳格に適用。

---

## 5. 実装手順 / Implementation Plan

Target Branch: `feat/222-implement-mitre-cwe-spider-and-catalog-ingestion`

### Step 1: 設計仕様書（DSN-06, DSN-20）の先行改訂
1. `DSN-06` に `CweSpider` のアーキテクチャ、許可ドメイン、Politeness 設定（5.0s）、キャッシュ戦略を追記。
2. `DSN-20` に `cti_cwes` および `cti_cwe_relationships` の DDL スキーマ、CWE REST API インジェスト仕様、因果ホップ（論文 2 ホップ vs 脆弱性 1 ホップ）を反映。

### Step 2: `cti_catalog_db` ストレージ層の拡張 (`storage.py`)
1. `src/domain/security/cti/storage.py` に `cti_cwes` および `cti_cwe_relationships` テーブル DDL を追加。
2. CWE エンティティの挿入・一括インサート・キー検索・階層探索メソッドを実装。
3. `manage.py tables` および `manage.py inspect cti_cwes` でテーブルが正しく認識されることを確認。

### Step 3: `CweSpider` の実装 ＆ スパイダー登録
1. `src/domain/security/spiders/cwe_spider.py` を実装（ゼロ外部依存 Pure-Python、`urllib.request` / `json`）。
2. MITRE CWE REST API (`https://cwe-api.mitre.org/api/v1/cwe/weakness`) または公式データフィードを取得し、`ScrapedItem`（`cwe_id`, `name`, `abstraction`, `top25_rank`, `description`, `mitigations`, `related_attack_ids`）へ正規化。
3. `src/domain/security/plugin.py` の `get_spiders()` に `cwe_spider: CweSpider` を登録。
4. `src/spider/spiders/cwe_spider.py` に後方互換ラッパーを配置。

### Step 4: タクソノミー ＆ オントロジー因果結合
1. `src/domain/security/taxonomy/cwe.py` を更新し、`CWE_DEFENSE_MAP` に未定義の弱点であっても `cti_catalog_db` から動的に緩和策や名称を補完解決できる透過インターフェースを提供。
2. `src/ontology/seeder.py` において、CWE ノードのオントロジーインジェストおよび CVE から CWE への因果リレーション（`cve:affectsWeakness`）の結合を検証。

### Step 5: テスト作成 ＆ 品質ゲート検証
1. `tests/domain/security/spiders/test_cwe_spider.py` にモックレスポンスを用いた契約パーステストを実装。
2. `tests/domain/security/cti/test_cwe_storage.py` にストレージ層の CRUD・リレーションテストを実装。
3. `make check` (`isort`, `black`, `flake8`, `mypy --strict`, `xenon` Grade A) を 100% 通過させる。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `CweSpider` が `src/domain/security/spiders/cwe_spider.py` に実装され、ゼロ外部依存 Pure-Python で正常に動作すること。
- [x] `src/domain/security/plugin.py` および `src/spider/registry.py` に `cwe_spider` が登録され、CLI から実行可能であること。
- [x] `cti_catalog_db` に `cti_cwes` および `cti_cwe_relationships` テーブルが追加され、`./manage.py inspect cti_cwes` で確認できること。
- [x] CWE の Weakness ID、名称、抽象度、Top 25 該否、緩和策が正しく `ScrapedItem` および DB カタログに格納されること。
- [x] `src/domain/security/taxonomy/cwe.py` が動的カタログ連携に対応し、未知の CWE に対しても定義を解決できること。
- [x] `DSN-06` および `DSN-20` が実態に合わせて更新されていること。
- [x] 新規単体テスト（スパイダーパース、ストレージ）が追加され、全件 PASS すること。
- [x] `make static_analysis`（mypy strict 0 エラー、xenon Grade A）を 100% 満たすこと。
- [x] `docs/issues/README.md` の Issue 222 ステータスが適切に管理されていること。
