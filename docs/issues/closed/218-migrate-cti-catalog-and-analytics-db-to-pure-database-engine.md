---
ID: 218
種別: Feature / Refactor
優先度: High
ステータス: Closed (Completed)
完了日: 2026-09-08
担当エージェント: Project Manager (PM) / Systems Architect / Database Specialist / Software Quality Assurance Specialist / Information Security Specialist
---

# [FEAT/REF] cti_catalog.db および analytics.db の src/database 独自データベース移行とデータマイグレーション (ID: 218)

## 1. 概要 / Summary

現在、脅威インテリジェンス（MITRE ATT&CK / CISA KEV）を管理する `outputs/database/catalog/cti_catalog.db`（約2.4MB、計2,685件の戦術・技法・緩和策・関係性・KEVデータ）およびシステム分析・KPI時系列メトリクスを管理する `outputs/database/analytics/analytics.db`（約64KB、メトリクス履歴・KPIスナップショット・脅威トレンド）は、標準 SQLite ファイル形式（`.db`）を用いて永続化されている。

プロジェクト基本方針および先行する Issue 213（`graph.db` の独自DB移行 & 完全廃止）、Issue 214（単一 `.vdb` マルチテーブルコンテナ対応および PEP 249 互換インターフェース実装）、Issue 217（DBファイル定義のDI分離）に基づき、本システム内の全永続化基盤をゼロ外部依存・純粋 Python 実装の `src/database` 独自データベース（`.vdb` / MultiTableContainer `OKFMTC01` コンテナまたは `VectorStorage` / `SQLExecutor`）へ完全移行・統合する。

また、現在 `cti_catalog.db` および `analytics.db` に蓄積されている全レコードについて、データ損失ゼロの厳密なデータマイグレーション（抽出・変換・移管・整合性突合）を実施し、移行後の独自データベースに完全にデータを移管する。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-05 データベースエンジンアーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md) (Chapter 19 単一 .vdb マルチテーブルコンテナ & PEP 249 sqlite3 互換インターフェース)
- 設計書: [DSN-20 外部脅威インテリジェンス（CTI）取り込みおよびオントロジー・カタログ基盤包括的アーキテクチャ設計書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 関連 Issue:
  - [Issue 213: src/graph の永続化・クエリバックエンドへの src/database (自作DB基盤) 統合 & graph.db 完全廃止](closed/213-integrate-database-engine-into-graph-subsystem.md)
  - [Issue 214: src/database における単一 .vdb マルチテーブルコンテナ対応および sqlite3 (PEP 249) 互換インターフェースの実装](closed/214-support-multi-table-vdb-container-and-pep249-sqlite-interface.md)
  - [Issue 217: src/database からの具体的データベース指定・ファイルパス結合の完全排除と利用側一元定義（DI）の確立](closed/217-decouple-database-file-definitions-from-database-engine.md)
  - [Issue 215: データベース台帳 UI (#/database) における架空テーブル・モック表示の撤廃と実コンテナ・実SQLインスペクションへの刷新](215-fix-database-explorer-mock-data-and-real-sql-introspection.md)

---

## 3. 13大専門エージェント観点レビュー / Multi-Agent Review

1. **Project Manager (PM)**:
   - システム内の全DB（`papers`, `knowledge_graph`, `cti_catalog`, `analytics`）が純粋な独自DB（`.vdb`）に一本化され、アーキテクチャの統一性とゼロ外部依存性が達成される。既存データ（2,685件以上のCTIとKPI）の欠損が起きないようマイグレーション検証を義務付ける。
2. **Database / Data Infrastructure Specialist**:
   - `MultiTableVectorStorage`（`OKFMTC01`）または `sqlite_engine.py` の PEP 249 互換レイヤーを活用し、複数テーブル（`cti_tactics`, `cti_techniques`, etc.）を単一コンテナファイル内で堅牢に永続化・クエリ可能にする。
3. **Systems Architect**:
   - DIP（依存性逆転の原則）に基づき、利用側（`CTICatalogStorage`, `AnalyticsStorage`）が自身のファイルパス（`.vdb`）を一元定義し、コアエンジン側にはファイルパスをハードコードしない。
4. **Information Security Specialist**:
   - CTI Catalog はセキュリティ運用の中核データであるため、マイグレーション時のチェックサム突合、SQL パラメータバインディングの徹底、コンテナ SuperBlock CRC32 検証による耐改ざん性を確保する。
5. **Software Quality Assurance (SQA) Specialist**:
   - マイグレーション前後の全テーブル件数およびキー値の 100% 一致検証、単体テスト・結合テストの全件 PASS、`mypy --strict`、`xenon`（Grade A）の品質ゲートを死守する。
6. **Network Specialist**:
   - CTI および Analytics のマイグレーションはオフラインで安全に実行可能であり、外部通信に影響を与えないことを保証する。
7. **IT Specialist (NLP & Info Retrieval)**:
   - `cti_techniques_fts` 等の全文検索について、SQLite FTS5 仮想テーブルに過度に依存せず、`src/database` の BM25 / LIKE 探索エンジンと協調動作できるようクエリ互換性を担保する。
8. **IT Strategist**:
   - `analytics.db` に格納されている戦略 KPI（`strategic_kpis`）および脅威トレンド（`threat_trends`）の連続性を保護し、ダッシュボードでの可視化が途切れないようにする。
9. **IT Service Manager**:
   - 移行時のロールバック手段として、旧 `.db` ファイルを直ちに破棄せず、`.bak` として保全した上で新 `.vdb` への切り替えを行う。
10. **Embedded Systems Specialist**:
    - リソース制約のある環境でも高速に読み書きできるよう、ファイル I/O のオーバーヘッドを最小化する。
11. **Systems Auditor**:
    - 移行ログ（移行日時、ソースDB、ターゲットDB、各テーブルの移行件数、検証結果）を明瞭に出力し、トレーサビリティを確立する。
12. **UI/UX & Documentation Designer**:
    - Web UI の Database Explorer（`#/database`）において、新 `.vdb` コンテナ（`cti_catalog.vdb`, `analytics.vdb`）が認識され、テーブル一覧と件数が正しく表示されることを確認する。
13. **Education Specialist**:
    - マイグレーションスクリプトに詳細な docstring と実行手順を記載し、開発者が容易に再実行・検証できるようにする。

---

## 4. セキュリティ & 脅威モデル分析 / Security & Threat Modeling (STRIDE)

| 脅威 / 脆弱性 (STRIDE) | リスク評価 | 対策と実装方針 |
| :--- | :--- | :--- |
| **ファイル偽造・破損 (Spoofing / Tampering)** | High | `MultiTableVectorStorage` ロード時に SuperBlock の Magic Bytes（`b"OKFMTC01"`）、バージョン番号、および CRC32 チェックサムを検証し、不正・破損ファイルを遮断。 |
| **SQL インジェクション (Tampering)** | High | テーブル移行およびデータ参照クエリにおいて、文字列連結による SQL 構築を排除し、必ず `?` プレースホルダーによる型安全パラメータバインディングを強制。 |
| **パストラバーサル (Information Disclosure / Tampering)** | Medium | `storage_path` 引数に対して `is_safe_workspace_path` による境界チェックを実施し、ワークスペース外や任意ディレクトリへの書き出しを拒絶。 |
| **データ不整合・欠損 (Repudiation / Tampering)** | High | マイグレーション処理の最後に、ソース DB とターゲット DB の全テーブル件数および主要レコードの完全一致を検証し、1件でも不一致があればロールバック・例外送出。 |
| **リソース枯渇 / DoS (Denial of Service)** | Medium | マイグレーション時のバッチ書き込みチャンクサイズを適切に設定し、大容量テーブルでもメモリ消費量を制御。 |

---

## 5. 移行対象データとテーブル詳細仕様 / Target Tables & Migration Spec

### 5.1. CTI Catalog (`cti_catalog.db` -> `cti_catalog.vdb`)
- **ソースファイル**: `outputs/database/catalog/cti_catalog.db` (2,433,024 bytes)
- **ターゲットファイル**: `outputs/database/catalog/cti_catalog.vdb`
- **対象テーブルと実測件数**:
  1. `cti_tactics` (15 rows): 戦術ID, shortname, name, description, external_url
  2. `cti_techniques` (697 rows): 技法ID, name, description, is_subtechnique, parent_technique_id, platforms_json, tactics_json, external_url, stix_id
  3. `cti_mitigations` (44 rows): 緩和策ID, name, description, external_url, stix_id
  4. `cti_relationships` (1,923 rows): source_id, target_id, rel_type (複合主キー)
  5. `cisa_kev_vulnerabilities` (6 rows): cve_id, vendor_project, product, vulnerability_name, date_added, short_description, required_action, due_date, known_ransomware_campaign_use, notes
  - *Note*: `cti_techniques_fts`（FTS5 仮想テーブル）は実テーブル `cti_techniques` から生成されるため、新エンジン環境下で再構築または LIKE/BM25 互換クエリで処理する。

### 5.2. Analytics Storage (`analytics.db` -> `analytics.vdb`)
- **ソースファイル**: `outputs/database/analytics/analytics.db` (65,536 bytes)
- **ターゲットファイル**: `outputs/database/analytics/analytics.vdb`
- **対象テーブルと実測件数**:
  1. `threat_trends` (6 rows): name, category, count, prev_count, growth_pct, sample_ids, updated_at
  2. `strategic_kpis` (13 rows): kpi_key, kpi_category, num_value, text_value, metadata_json, updated_at
  3. `metrics_history` (6 rows): id, snapshot_json, collected_at, created_epoch
  4. `latest_snapshot` (1 rows): snapshot_key, snapshot_json, updated_at, updated_at_epoch
  - *Note*: `papers` テーブル（0 rows）は旧スキーマ残滓のため移行不要または空テーブルとして保持。

---

## 6. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/domain/security/cti/storage.py](../../src/domain/security/cti/storage.py) - `CTICatalogStorage` のデフォルトパスを `cti_catalog.vdb` に更新し、PEP 249 / 独自DB接続を統合
- [x] [src/analytics/storage.py](../../src/analytics/storage.py) - `AnalyticsStorage` のデフォルトパスを `analytics.vdb` に更新し、PEP 249 / 独自DB接続を統合
- [x] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py) - `.vdb` 拡張子ファイルに対する透過的 PEP 249 互換接続およびマルチテーブルサポートの動作保証
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) - `_introspect_catalog_database`, `_introspect_analytics_database` のターゲットパスを `.vdb` に更新
- [x] [scripts/migrate_catalog_and_analytics.py](../../scripts/migrate_catalog_and_analytics.py) (新規) - `cti_catalog.db` と `analytics.db` の全データを新 `.vdb` へ安全移行するバッチスクリプト
- [x] [tests/test_vdb_migration_full.py](../../tests/test_vdb_migration_full.py) (新規) - CTI および Analytics の新 `.vdb` マイグレーション完全性、CRUD 操作、永続性検証テストスイート

---

## 7. 実装方針と詳細ステップ / Implementation Plan

Target Branch: `feat/218-migrate-cti-catalog-and-analytics-db-to-pure-database-engine`

### Step 1: マイグレーションスクリプトの実装 (`scripts/migrate_catalog_and_analytics.py`)
1. 旧 `cti_catalog.db` および `analytics.db` から全テーブル定義（DDL）および全レコードを抽出。
2. 新ターゲットパス `outputs/database/catalog/cti_catalog.vdb` および `outputs/database/analytics/analytics.vdb` に対して `get_sqlite_connection` または `connect` を用い、テーブル作成とレコード一括挿入（`INSERT OR REPLACE`）を実行。
3. 移行直後にレコード件数突合（Count Match Validation）を実施し、1件の過不足もないことを自動判定。
4. 旧 `.db` ファイルを安全のため `.db.bak` としてバックアップ退避。

### Step 2: `CTICatalogStorage` (`src/domain/security/cti/storage.py`) の刷新
1. `DEFAULT_DB_PATH` を `outputs/database/catalog/cti_catalog.vdb` に変更。
2. `_init_schema` において、FTS5 仮想テーブルがサポートされない環境（独自DB純粋モード）でも動作するように条件分岐または LIKE/BM25 互換フォールバックを組み込む。
3. クエリメソッド群（`insert_technique`, `get_technique`, `search_techniques_fts`, `get_stats`, etc.）が新 `.vdb` に対して完全に動作することを確認。

### Step 3: `AnalyticsStorage` (`src/analytics/storage.py`) の刷新
1. `__init__` のデフォルト `db_name` を `"analytics.vdb"` に変更。
2. `initialize_db` のマイグレーションスクリプト適用が `.vdb` 上で問題なく動作することを確認。
3. スナップショット保存・読み出し（`save_snapshot`, `load_latest_snapshot`）、KPI 更新、メトリクス履歴の書き込み・取得が正常に動作することを確認。

### Step 4: Web ゲートウェイ (`src/web/gateway/handlers.py`) のインスペクション連携
1. `_introspect_catalog_database` および `_introspect_analytics_database` の検索パスを `.vdb` に更新。
2. Database Explorer API 経由で各テーブル（`cti_techniques`, `strategic_kpis` 等）のライブ件数が正確に返却されることを確認。

### Step 5: テストスイートの実装と検証
1. `tests/` に CTI および Analytics の新 `.vdb` に対する単体・結合テストを追加・更新。
2. `:memory:` モードおよび通常ファイルモードの双方が動作することを検証。

### Step 6: 品質ゲートの検証と Issue クローズ準備
1. `make test`, `make static_analysis`, `mypy --strict`, `make check_format` を実行し、全件 PASS を確認。
2. 全ファイル内のリンク検証（絶対パス `file:///` 0件）。

---

## 8. 完了条件 / Success Criteria (DoD)

- [x] `outputs/database/catalog/cti_catalog.vdb` に旧 `cti_catalog.db` の全レコード（`cti_tactics`: 15件, `cti_techniques`: 697件, `cti_mitigations`: 44件, `cti_relationships`: 1,923件, `cisa_kev_vulnerabilities`: 6件）が損失ゼロで完全に移行されていること。
- [x] `outputs/database/analytics/analytics.vdb` に旧 `analytics.db` の全レコード（`threat_trends`: 6件, `strategic_kpis`: 13件, `metrics_history`: 6件, `latest_snapshot`: 1件）が損失ゼロで完全に移行されていること。
- [x] `CTICatalogStorage` が `outputs/database/catalog/cti_catalog.vdb` を正系として参照し、技法・戦術・緩和策の登録・検索・統計取得がすべて正常動作すること。
- [x] `AnalyticsStorage` が `outputs/database/analytics/analytics.vdb` を正系として参照し、メトリクス保存・最新スナップショット取得・KPI更新がすべて正常動作すること。
- [x] `src/web/gateway/handlers.py` のデータベースインスペクションにおいて、新 `.vdb` コンテナのテーブル名および正確なレコード件数が返却されること。
- [x] `scripts/migrate_catalog_and_analytics.py` が提供され、冪等かつ安全にマイグレーションが再実行可能であること。
- [x] ドキュメントおよびソースコード内のリンクに絶対パス（`file:///`）が 0 件であること。
- [x] `make test`, `make static_analysis`, `mypy --strict` のトリプル品質ゲートが 100% PASS すること。
