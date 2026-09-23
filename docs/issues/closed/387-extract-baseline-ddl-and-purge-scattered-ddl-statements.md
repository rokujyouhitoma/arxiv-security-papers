---
ID: 387
種別: Refactor
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 現行DDLベースライン化＆散在DDL全廃リファクタリング (Phase 4) (ID: 387)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、現在システム各所（データアクセス層、リポジトリ、初期化スクリプト等）に散在している `CREATE TABLE` / `CREATE INDEX` 発行ロジックを完全抽出し、第一優先の自作DB（`src/database/`）および第二優先として正式対応する SQLite（`sqlite3`）の双方で完全互換となるベースラインマイグレーション `migrations/0001_baseline.up.sql` および `migrations/0001_baseline.down.sql` として一本化する。
マイグレーションファイル名には通し番号プレフィックス `0001_` を採用し、マイグレーションエンジン（`models.py` / `manager.py`）を連番プレフィックスに対応させる。
同時に、アプリケーションコード内の散在 DDL 発行コード（`src/analytics/storage.py`, `src/spider/daemon/storage.py`, `src/domain/security/cti/storage.py`）を整理・全廃し、DB スキーマ初期化をマイグレーションエンジンへ完全移管する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第3章、第8章、第9章、第11.2節 (Phase 4)
- 依存 Issue: [Issue #386](docs/issues/closed/386-implement-migrations-cli-command-and-manage-py-integration.md) (Phase 3: CLIコマンド＆管理統合)
- ユーザー指定: `migrationsには 0001_ という通し番号を入れてください。`

---

## 3. セキュリティ要件・脅威モデル (STRIDE)

| 脅威分類 | リスクシナリオ | 緩和策 |
| :--- | :--- | :--- |
| **Tampering** | マイグレーションファイル名やSQL文の不正改ざん | ファイル名検証正規表現で英数字・アンダースコアおよび安全な連番形式（`0001_`等）を強制。ディレクトリトラバーサルを拒絶。 |
| **Denial of Service** | 散在DDL削除に伴うテーブル未作成エラーや起動時クラッシュ | テーブルが存在しない場合のフォールバックや起動前マイグレーション自動実行/明示チェックを整備。 |
| **Information Disclosure** | DDLロールバック時（`down`）の不要データ漏洩・誤消去 | `.down.sql` では依存関係の逆順（インデックス -> 外部キー参照先 -> 親テーブル）で安全に `DROP TABLE/INDEX IF EXISTS` を実行。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [migrations/0001_baseline.up.sql](file:///workspace/arxiv-security-papers/migrations/0001_baseline.up.sql)
- [x] [migrations/0001_baseline.down.sql](file:///workspace/arxiv-security-papers/migrations/0001_baseline.down.sql)
- [x] [src/database/migrations/models.py](file:///workspace/arxiv-security-papers/src/database/migrations/models.py) (連番 `0001_` 等の通し番号プレフィックスに対応する正規表現パターン拡張)
- [x] [src/database/migrations/manager.py](file:///workspace/arxiv-security-papers/src/database/migrations/manager.py) (通し番号を含むファイル生成・ソート順整合性保証)
- [x] [src/analytics/storage.py](file:///workspace/arxiv-security-papers/src/analytics/storage.py) (`SCHEMA_MIGRATIONS` 内のインライン DDL を廃止し、マイグレーション基盤へ委譲)
- [x] [src/spider/daemon/storage.py](file:///workspace/arxiv-security-papers/src/spider/daemon/storage.py) (`_init_tables` の散在 DDL を整理)
- [x] [src/domain/security/cti/storage.py](file:///workspace/arxiv-security-papers/src/domain/security/cti/storage.py) (`_init_schema` 内のリレーショナルテーブル DDL を整理)
- [x] [tests/test_database_migrations_baseline.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_baseline.py) (ベースラインマイグレーションの PyDB / SQLite 両対応 E2E 検証)
- [x] [tests/test_database_migrations_connection.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_connection.py) (通し番号ファイル名パースのテスト)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `refactor/387-baseline-ddl-and-purge-scattered-ddl`

1. **マイグレーションファイル名規則の通し番号対応 (`0001_`)**:
   - `MIGRATION_FILENAME_PATTERN`: `r"^(\d{4}_\d{14}|\d{14}|\d{4})_([a-z0-9_]+)\.(up|down)\.sql$"` に更新。
   - `0001_baseline.up.sql`（version: `0001`, name: `baseline`）を正しく認識し、自然順ソートで順序正しく実行。
   - `manager.create(name)` メソッドで既存ファイルの最大通し番号を検知し、次の番号（例: `0002_`）を自動採番するロジックを導入。

2. **ベースライン DDL ファイルの作成 (`0001_baseline.up.sql`, `0001_baseline.down.sql`)**:
   - 以下の全リレーショナルテーブルとインデックスを ANSI SQL 互換（PyDB `SQLExecutor` + `sqlite3`）で記述：
     - `threat_trends`, `strategic_kpis`, `metrics_history`, `latest_snapshot` (Analytics) + インデックス
     - `spider_execution_logs` (Spider)
     - `cti_tactics`, `cti_techniques`, `cti_mitigations`, `cti_relationships`, `cti_cwes`, `cti_cwe_relationships`, `cisa_kev_vulnerabilities` (CTI) + インデックス
   - `0001_baseline.down.sql` には逆順で全テーブルとインデックスの `DROP TABLE IF EXISTS` / `DROP INDEX IF EXISTS` を記述。

3. **散在 DDL 発行コードの全廃・移管**:
   - `src/analytics/storage.py`: `SCHEMA_MIGRATIONS` からテーブル生成 DDL を削除し、マイグレーション適用状態に依存するか、マイグレーションマネージャ経由で初期化するよう安全にリファクタリング。
   - `src/spider/daemon/storage.py`: `_init_tables()` を整理。
   - `src/domain/security/cti/storage.py`: リレーショナルテーブル作成をベースライン DDL に委譲。

4. **テスト作成と品質ゲート検証**:
   - `tests/test_database_migrations_baseline.py` を作成し、Primary (PyDB) および Secondary (SQLite) の双方で `migrations up` -> 全テーブル存在確認 -> `migrations down` -> 全テーブル削除確認 -> `migrations up` (再適用・冪等性確認) を網羅。
   - `make check_format`, `xenon --max-absolute A`, `mypy --strict src` を実行し品質ゲート 100% 合格を達成。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `migrations/0001_baseline.up.sql` および `0001_baseline.down.sql` が正しく配置されていること。
- [x] 通し番号 `0001_` を含むマイグレーションファイルが `models.py` / `manager.py` / `cli.py` で完全にサポートされていること。
- [x] `src/` 配下のアドホックな DDL 発行コードが整理・全廃され、スキーマ管理がマイグレーションへ一本化されていること。
- [x] Primary (`pydb`) と Secondary (`sqlite`) の双方でベースラインマイグレーションの前進（up）・巻き戻し（down）がノーエラーで完全動作すること。
- [x] 既存の全単体・統合テストおよび新規作成した `test_database_migrations_baseline.py` が PASS すること。
- [x] `make check_format`, `xenon` (Rank A), `mypy --strict` のトリプル品質ゲートを 100% クリアすること。


