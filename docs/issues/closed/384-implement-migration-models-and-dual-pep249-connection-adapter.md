---
ID: 384
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] データモデル・PEP 249 デュアル接続アダプタ基盤の実装 (Phase 1) (ID: 384)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、データベースマイグレーションツールの基盤層となるデータモデル定義、自作DB（第一優先: `src/database/`）および SQLite（第二優先・正式対応: `sqlite3`）に対応した PEP 249 デュアル接続アダプタ、および `schema_migrations` 管理テーブル初期化・インスペクタ機構を実装する。
優先度として自作DB（`src.database.driver` / SlottedPage / ARIES WAL）をプロジェクトの標準・最優先ターゲットとしつつ、SQLite環境でも本番運用可能なレベルで正式サポートするマルチデータベース接続基盤を確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第3章、第4章、第5章、第11.2節 (Phase 1)
- 関連アーキテクチャ: [DSN-05 自作Pure Python RDBMSアーキテクチャ仕様](docs/designs/DSN-05-pure_python_rdbms_architecture_specification.md)
- セキュリティ設計: STRIDE 脅威分析（パストラバーサル防止、SQLインジェクション防壁、改ざん耐性）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/migrations/__init__.py](file:///workspace/arxiv-security-papers/src/database/migrations/__init__.py) (新規公開インターフェース)
- [x] [src/database/migrations/models.py](file:///workspace/arxiv-security-papers/src/database/migrations/models.py) (新規バリューオブジェクト・列挙型・バリデータ)
- [x] [src/database/migrations/connection.py](file:///workspace/arxiv-security-papers/src/database/migrations/connection.py) (新規PEP 249アダプタ基盤)
- [x] [src/database/migrations/inspector.py](file:///workspace/arxiv-security-papers/src/database/migrations/inspector.py) (新規スキーマ検査器)
- [x] [tests/test_database_migrations_connection.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_connection.py) (新規単体テストスイート)

---

## 4. セキュリティ要件と STRIDE 脅威分析

| 脅威項目 | 潜在リスク | 本 Issue における緩和策 |
| :--- | :--- | :--- |
| **Spoofing / Tampering** | 意図しないファイルパスの読み込み（パストラバーサル） | ファイル名およびマイグレーション名は `^[0-9]{14}_[a-z0-9_]+\.(up|down)\.sql$` の正規表現でホワイトリスト検証。`..` や `/` などの記号を拒絶。 |
| **Tampering** | 不正な DDL によるシステムカタログ破損 | `schema_migrations` に対する DDL/DML は完全にパラメータ化または定数化し、外部入力の生連結を一切排除。 |
| **Elevation of Privilege** | バックエンド指定における不正文字列インジェクション | `BackendType` Enum（`pydb`, `sqlite`）により型安全に制御。無効な文字列は即座に例外送出。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/384-implement-migration-models-and-dual-pep249-connection-adapter`

1. **データモデル定義 (`src/database/migrations/models.py`)**:
   - `BackendType`: `Enum("BackendType", ["PYDB", "SQLITE"])` の定義。文字列との相互変換（`from_str`）および既定値（`PYDB`）の明示。
   - `MigrationStatus`: `Enum("MigrationStatus", ["APPLIED", "PENDING"])` の定義。
   - `MigrationFile`: 不変データクラス（`version: str`, `name: str`, `direction: str`, `filepath: Path`）。
   - `MigrationRecord`: `schema_migrations` レコード表現（`version: str`, `name: str`, `applied_at: str`, `execution_time_ms: int`, `checksum: Optional[str]`）。
   - 正規表現バリデータ: `validate_migration_filename(filename: str)` および `validate_migration_name(name: str)`。不正文字混入時は `ValueError` を送出。

2. **PEP 249 デュアル接続アダプタ (`src/database/migrations/connection.py`)**:
   - `DatabaseAdapter` 抽象基底クラス（Protocol / ABC）:
     - `connect() -> Any`: PEP 249 準拠のコネクションを生成。
     - `execute_ddl(sql: str) -> None`: DDL 文の実行。
     - `is_healthy() -> bool`: ヘルスチェック。
     - `backend_type: BackendType` プロパティ。
   - `PyDBAdapter`（第一優先: Primary）:
     - `src.database.driver.connect(database=str(db_path))` による自作 Pure Python RDBMS 接続。
     - トランザクション・ARIES WAL コミットフラッシュ制御。
   - `SQLiteAdapter`（第二優先: Secondary正式対応）:
     - 標準 `sqlite3.connect(str(db_path))` による接続。
     - `PRAGMA foreign_keys = ON;`, `PRAGMA journal_mode = WAL;` の自動設定。
   - `get_adapter(backend: BackendType | str, db_path: Path | str) -> DatabaseAdapter` ファクトリ関数。

3. **スキーマインスペクタ (`src/database/migrations/inspector.py`)**:
   - `SchemaInspector` クラス:
     - `ensure_schema_migrations_table(adapter: DatabaseAdapter) -> None`:
       - `CREATE TABLE IF NOT EXISTS schema_migrations (...)` の発行。
       - 自作DB（Primary）および SQLite（Secondary）の双方で共通利用可能な標準 DDL。
     - `has_schema_migrations_table(adapter: DatabaseAdapter) -> bool`:
       - 管理テーブルの存在確認。
     - `get_applied_migrations(adapter: DatabaseAdapter) -> List[MigrationRecord]`:
       - `SELECT version, name, applied_at, execution_time_ms, checksum FROM schema_migrations ORDER BY version ASC` による適用履歴取得。

4. **モジュール公開エクスポート (`src/database/migrations/__init__.py`)**:
   - `BackendType`, `MigrationFile`, `MigrationRecord`, `MigrationStatus`, `DatabaseAdapter`, `PyDBAdapter`, `SQLiteAdapter`, `get_adapter`, `SchemaInspector` をエクスポート。

5. **包括的単体テスト (`tests/test_database_migrations_connection.py`)**:
   - データモデルのバリデーションテスト（正常系・不正名・パストラバーサル拒絶）。
   - 自作DBアダプタの接続・DDL発行・テーブル作成・クエリテスト。
   - SQLiteアダプタの接続・DDL発行・テーブル作成・クエリテスト。
   - `SchemaInspector` による `schema_migrations` 自動作成の冪等性テスト（2回呼出してもエラーにならないこと）。
   - 履歴レコード取得の正確性テスト。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/database/migrations/` 配下に `__init__.py`, `models.py`, `connection.py`, `inspector.py` が新規作成されていること。
- [x] 第一優先の自作DB（`pydb`）および第二優先のSQLite（`sqlite`）の双環境で `schema_migrations` 管理テーブルが冪等に作成・取得できること。
- [x] パストラバーサル（`../` 等）や不正なマイグレーション名に対するバリデーション例外テストが 100% PASS すること。
- [x] `pytest tests/test_database_migrations_connection.py` が全件 PASS すること。
- [x] `mypy --strict src/database/migrations/` がエラー 0 件で通過すること。
- [x] `flake8` および `xenon` 複雑度基準（ランクA）を満たしていること。
