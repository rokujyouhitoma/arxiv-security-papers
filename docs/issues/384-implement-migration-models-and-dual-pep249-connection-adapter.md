---
ID: 384
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] データモデル・PEP 249 デュアル接続アダプタ基盤の実装 (Phase 1) (ID: 384)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、データベースマイグレーションツールの基盤層となるデータモデル定義、自作DB（第一優先: `src/database/`）および SQLite（第二優先・正式対応: `sqlite3`）に対応した PEP 249 デュアル接続アダプタ、および `schema_migrations` 管理テーブル初期化・インスペクタ機構を実装する。
優先度として自作DBをプロジェクトの標準・最優先ターゲットとしつつ、SQLite環境でも本番運用可能なレベルで正式サポートするマルチデータベース接続基盤を確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第4章、第5章、第11.2節 (Phase 1)
- 関連アーキテクチャ: [DSN-05 自作Pure Python RDBMSアーキテクチャ仕様](docs/designs/DSN-05-pure_python_rdbms_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/database/migrations/__init__.py](file:///workspace/arxiv-security-papers/src/database/migrations/__init__.py)
- [ ] [src/database/migrations/models.py](file:///workspace/arxiv-security-papers/src/database/migrations/models.py)
- [ ] [src/database/migrations/connection.py](file:///workspace/arxiv-security-papers/src/database/migrations/connection.py)
- [ ] [src/database/migrations/inspector.py](file:///workspace/arxiv-security-papers/src/database/migrations/inspector.py)
- [ ] [tests/test_database_migrations_connection.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_connection.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/384-migration-models-and-dual-connection-adapter`

1. **データモデル定義 (`models.py`)**:
   - `MigrationFile`, `MigrationRecord`, `MigrationStatus`, `BackendType` (`pydb` [第一優先] / `sqlite` [第二優先・正式対応]) 等の不変値オブジェクト（dataclass）を定義する。
   - バリデーション関数（14桁UTCタイムスタンプ、ファイル名正規表現、パストラバーサル防止）を実装する。
2. **PEP 249 デュアル接続アダプタ (`connection.py`)**:
   - `DatabaseAdapter` 抽象基底プロトコルを策定する。
   - `PyDBAdapter`（第一優先）: `src.database.driver.connect()` による自作DB接続とARIESトランザクション制御。
   - `SQLiteAdapter`（第二優先）: 標準ライブラリ `sqlite3.connect()` による接続と排他トランザクション制御。
   - ファクトリ関数 `get_adapter(backend: BackendType, db_path: Path)` を実装し、未指定時のデフォルトを `BackendType.PYDB` とする。
3. **スキーマインスペクタ (`inspector.py`)**:
   - `schema_migrations` テーブルの存在検査、自動作成DDL発行、および適用済みマイグレーション履歴の読み取り処理を実装する。
4. **単体テスト整備 (`tests/test_database_migrations_connection.py`)**:
   - 自作DB（`.vdb`）を主軸とし、SQLite（`.db`）も含めた双方のデータベース環境で初期化とメタデータ読み書きを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/migrations/` 配下に `models.py`, `connection.py`, `inspector.py` が新規作成されていること。
- [ ] 第一優先の自作DB（`pydb`）および第二優先のSQLite（`sqlite`）の双環境で `schema_migrations` 管理テーブルが冪等に作成・取得できること。
- [ ] パストラバーサルや不正なマイグレーションファイル名に対するバリデーション例外テストが網羅されていること。
- [ ] `pytest tests/test_database_migrations_connection.py` が全件 PASS すること。
- [ ] `mypy --strict src/database/migrations/` がエラー 0 件で通過すること。
