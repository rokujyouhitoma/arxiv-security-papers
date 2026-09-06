---
ID: 196
種別: Architecture / Refactor
優先度: High
ステータス: Closed
Created At: 2026-09-06T21:25:30+09:00
Closed At: 2026-09-06T21:44:00+09:00
---

# [ARCH/REFACTOR] cti_catalog_db および analytics_db の src/database (自作DBエンジン) 活用とドメイン分離の徹底 (ID: 196)

## 1. 概要 / Summary

`cti_catalog_db`（MITRE ATT&CK CTI カタログ）および `analytics_db`（時系列脅威動向・KPI・スナップショット）において、自作ゼロ依存データベース基盤 `src/database`（DSN-05）を正式なストレージ・クエリエンジンとして活用する。

### 厳格なクリーンアーキテクチャ境界の遵守
- **インフラ層 (`src/database/`)**:
  - ドメインの用語（`cti_tactics`, `cti_techniques`, `threat_trends`, `strategic_kpis`, `MITRE ATT&CK` 等）を一切含めず、純粋な汎用データベースエンジン（汎用テーブル管理、クエリ実行、接続管理、汎用イントロスペクション）として保つ。
- **ドメイン層 (`src/domain/security/cti/` & `src/analytics/`)**:
  - 各ドメインのスキーマ定義、テーブル構造、ビジネスロジック、マイグレーションはドメイン層自身が保持し、永続化エンジンとして `src/database` の汎用基盤APIを利用する。
- **依存関係の方向**:
  - `Domain Layer` -> `src/database` (汎用インフラ層)。`src/database` がドメイン層を知ることは決してない。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-05 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md)
- 設計書: [DSN-20 外部セキュリティ知識データセット統合インジェスト・ローカルカタログ管理基盤設計仕様書](../designs/DSN-20-external_security_knowledge_ingestion_and_catalog_architecture.md)
- 過去Issue: [Issue 149: sqlite利用箇所のsrc/database統合](149-integrate-src-database-engine-for-analytics-storage.md)
- 過去Issue: [Issue 195: データベース・ストレージ台帳の専用独立タブ化およびマルチデータベース統合インスペクション](195-separate-database-explorer-tab-and-support-multi-database.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/compat/sqlite_engine.py](../../src/database/compat/sqlite_engine.py) (汎用マルチDBテーブル検査・汎用データ移行同期ユーティリティの拡充)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (汎用ユーティリティのエクスポート)
- [x] [src/domain/security/cti/storage.py](../../src/domain/security/cti/storage.py) (CTIメタデータ自己記述、データ移行機能および `src/database` 経由イントロスペクションAPI)
- [x] [src/analytics/storage.py](../../src/analytics/storage.py) (Analyticsメタデータ自己記述、データ移行機能および `src/database` 経由イントロスペクションAPI)
- [x] [src/web/gateway/handlers.py](../../src/web/gateway/handlers.py) (各ドメインストレージのイントロスペクションAPI呼び出しへの一本化)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/196-integrate-src-database-engine-for-cti-and-analytics`

1. **`src/database`（純粋インフラ）の汎用性担保と汎用データ移行基盤**:
   - `src/database/compat/sqlite_engine.py` に、ドメイン非依存の汎用テーブル検査ユーティリティ（`get_sqlite_table_counts`）を整備。
   - SQLite ↔ 自作ストレージ（バイナリ VDB / SlottedPage）間の汎用テーブルデータ双方向ダンプ・同期ユーティリティ（`dump_sqlite_table_records`, `restore_sqlite_table_records`）を追加。ドメイン固有の名前・構造は一切持ち込まず、任意のテーブル・行構造に対応。

2. **ドメイン層におけるデータ移行（Migration）機能の実装**:
   - `src/domain/security/cti/storage.py`:
     - 既存の `cti_catalog.db` 内の全データ（tactics, techniques, mitigations, relationships）を汎用移行基盤経由でエクスポート／インポート（FTS5全文検索インデックスの自動再構築を含む）可能な `export_catalog_dataset()` / `import_catalog_dataset()` を提供。
   - `src/analytics/storage.py`:
     - 既存の `analytics.db` 内の全データ（threat_trends, strategic_kpis, metrics_history, latest_snapshot）を汎用移行基盤経由でエクスポート／インポート可能な `export_analytics_dataset()` / `import_analytics_dataset()` を提供。

3. **ドメイン層におけるメタデータ自己記述と `src/database` の利用**:
   - `src/domain/security/cti/storage.py`:
     - CTI カタログテーブルのメタデータ定義をドメイン層内に保持。
     - `get_introspection_metadata()` メソッドを提供し、`src/database` の汎用接続・集計機能を用いて動的な行数・サイズを集計して返却。
   - `src/analytics/storage.py`:
     - アナリティクステーブルのメタデータ定義をドメイン層内に保持。
     - `get_introspection_metadata()` メソッドを提供し、`src/database` の汎用接続・集計機能を用いて動的な行数・サイズを集計して返却。

4. **Web Gateway イントロスペクションのリファクタリング**:
   - `src/web/gateway/handlers.py` 内にハードコードされていたドメインテーブル定義を撤去。
   - `CTICatalogStorage.get_introspection_metadata(workspace_dir)` および `AnalyticsStorage.get_introspection_metadata(workspace_dir)` を呼び出す形に移行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/database/` 配下に CTI や Analytics などのドメイン固有コード（テーブル名・ビジネス語彙）が一切存在しないこと。
- [x] `src/database` にドメイン非依存の汎用テーブルデータ移行（エクスポート／インポート）機能が実装されていること。
- [x] `cti_catalog_db` および `analytics_db` の実データ（既存レコード）が損失なくエクスポート・移行・復元検証可能であること。
- [x] `cti_catalog_db` および `analytics_db` の永続化・クエリ・行数計測が `src/database` の汎用インフラAPIを通じて実行されること。
- [x] `src/web/gateway/handlers.py` からハードコードされたドメインテーブル辞書が排除され、各ドメイン層のストレージにカプセル化されていること。
- [x] `tests/domain/`、`tests/analytics/`、`tests/web/` のテストが全件 PASS すること。
- [x] `make check_format` および `make static_analysis`（mypy strict, xenon Grade A）がエラー0件であること。
