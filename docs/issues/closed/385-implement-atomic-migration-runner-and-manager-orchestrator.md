---
ID: 385
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] トランザクション実行器＆MigrationManagerオーケストレータの実装 (Phase 2) (ID: 385)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、マイグレーションSQLスクリプトをアトミックに適用・記録するトランザクション実行器（`MigrationRunner`）および、`create`, `up`, `down`, `status` コマンドのコア業務ロジックを統合統制する `MigrationManager` オーケストレータを実装する。
優先度として自作DB（`src/database/`）での実行を最優先標準（既定値）としつつ、SQLite（`sqlite3`）環境でも同一ロジック・同一信頼性で動作するマルチデータベース対応エンジンを構築する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第5章、第6章、第7章、第11.2節 (Phase 2)
- 依存 Issue: [Issue #384](docs/issues/closed/384-implement-migration-models-and-dual-pep249-connection-adapter.md) (Phase 1: データモデル・接続アダプタ)
- 関連アーキテクチャ: [DSN-05 自作Pure Python RDBMSアーキテクチャ仕様](docs/designs/DSN-05-pure_python_rdbms_architecture_specification.md) (SlottedPage / ARIES WAL)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/migrations/models.py](file:///workspace/arxiv-security-papers/src/database/migrations/models.py) (例外ヒエラルキー定義の追加)
- [x] [src/database/migrations/runner.py](file:///workspace/arxiv-security-papers/src/database/migrations/runner.py) (新規トランザクション実行器)
- [x] [src/database/migrations/manager.py](file:///workspace/arxiv-security-papers/src/database/migrations/manager.py) (新規コアオーケストレータ)
- [x] [src/database/migrations/__init__.py](file:///workspace/arxiv-security-papers/src/database/migrations/__init__.py) (公開エクスポート更新)
- [x] [tests/test_database_migrations_runner.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_runner.py) (新規実行器単体・アトミックロールバックテスト)
- [x] [tests/test_database_migrations_manager.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_manager.py) (新規オーケストレータ総合結合テスト)

---

## 4. セキュリティ要件と STRIDE 脅威分析

| 脅威項目 | 潜在リスク | 本 Issue における緩和策 |
| :--- | :--- | :--- |
| **Spoofing / Tampering** | 悪意あるマイグレーションファイル名によるパストラバーサル | `validate_migration_name` および `parse_migration_filename` により英数字・アンダースコアのみを許可し `..` や `/` などの記号を拒絶。 |
| **Tampering** | SQL構文エラーや途中の障害による不完全なスキーマ残留 | DDL実行および `schema_migrations` 更新を単一トランザクション境界で囲み、障害時は即座に `conn.rollback()` を実行してディスク状態を100%巻き戻す。 |
| **Repudiation** | どのマイグレーションがいつ適用されたかの追跡性欠如 | `applied_at`（UTC ISO 8601）、実行所要時間（ミリ秒）、およびSHA-256チェックサムを `schema_migrations` に厳密に記録。 |
| **Denial of Service** | 巨大・複数ステートメント実行時のバッファ枯渇やロック膠着 | SQLステートメントの安全な逐次分割実行と明示的コネクションクローズ、トランザクションタイムアウト保護。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/385-atomic-migration-runner-and-manager`

1. **例外ヒエラルキーの定義 (`src/database/migrations/models.py`)**:
   - `MigrationError(Exception)`: マイグレーション基底例外。
   - `MigrationExecutionError(MigrationError)`: SQL実行・適用・ロールバック失敗時例外。
   - `MigrationFileNotFoundError(MigrationError)`: ロールバック対象の `.down.sql` 欠損時例外。

2. **アトミック実行器 (`src/database/migrations/runner.py`)**:
   - `MigrationRunner` クラス:
     - `__init__(adapter: DatabaseAdapter)`: 対象アダプタを保持。
     - `split_sql_statements(sql: str) -> List[str]`: コメント行（`--`）および空行を除外してセミコロン境界でSQL文を安全にパース・分割。
     - `compute_checksum(content: str) -> str`: SQLスクリプトの SHA-256 チェックサムを算出。
     - `apply(migration: MigrationFile) -> MigrationRecord`:
       - 第一優先自作DB（`BEGIN`）および第二優先SQLite（`BEGIN IMMEDIATE`）でトランザクションを開始。
       - 分割されたSQLステートメントを逐次 `cur.execute()`。
       - 所要ミリ秒を計測。
       - 同一トランザクション内で `SchemaInspector.record_migration(adapter, record)`（または直接 INSERT）を実行。
       - `conn.commit()`（自作DB ARIES WAL同期、SQLite WAL同期）。
       - 途中で例外が発生した場合は即座に `conn.rollback()` を呼び出し、`MigrationExecutionError` を送出。
     - `rollback(migration: MigrationFile) -> None`:
       - トランザクション開始。
       - `.down.sql` の全ステートメントを逐次実行。
       - 同一トランザクション内で `SchemaInspector.remove_migration_record(adapter, version)` を実行。
       - `conn.commit()`。
       - 例外発生時は `conn.rollback()` を呼び出し `MigrationExecutionError` を送出。

3. **コアオーケストレータ (`src/database/migrations/manager.py`)**:
   - `MigrationManager` クラス:
     - `__init__(db_path: Path | str, migrations_dir: Optional[Path | str] = None, backend: BackendType | str = BackendType.PYDB)`
     - `create(name: str) -> Tuple[Path, Path]`:
       - `validate_migration_name(name)` で検証。
       - UTC 14桁タイムスタンプ（`YYYYMMDDHHMMSS`）を生成。
       - `<timestamp>_<name>.up.sql` および `<timestamp>_<name>.down.sql` のテンプレートファイルを生成。
     - `get_migration_files(direction: str = "up") -> List[MigrationFile]`:
       - `migrations_dir` を走査し、`parse_migration_filename` で整流化してバージョン昇順でソート返却。
     - `status() -> List[Dict[str, Any]]`:
       - 全 `.up.sql` と `SchemaInspector.get_applied_migrations` を突合し、`APPLIED` / `PENDING`、適用日時、所要ミリ秒を含む一覧を生成。
     - `up(steps: Optional[int] = None) -> List[MigrationRecord]`:
       - 未適用のマイグレーションをバージョン昇順で抽出し、最大 `steps` 件まで順次 `runner.apply(m)` を実行。
       - 適用されたレコードのリストを返却。
     - `down(steps: int = 1) -> List[str]`:
       - 直近適用済みのマイグレーションを降順で最大 `steps` 件抽出し、対となる `.down.sql` を探索（未存在時は `MigrationFileNotFoundError` 送出）。
       - `runner.rollback(down_file)` を実行。
       - ロールバックされたバージョンのリストを返却。

4. **モジュール公開エクスポート (`src/database/migrations/__init__.py`)**:
   - `MigrationRunner`, `MigrationManager`, `MigrationError`, `MigrationExecutionError`, `MigrationFileNotFoundError` を追加エクスポート。

5. **包括的テストスイート**:
   - `tests/test_database_migrations_runner.py`:
     - SQL分割ロジックの網羅的テスト（単一行、複数行、インラインコメント、末尾セミコロン有無）。
     - PyDB / SQLite 双方での正常適用とロールバック。
     - 意図的な SQL エラー混入時の完全自動ロールバック（テーブルが存在しないこと、台帳がクリーンであることの検証）。
   - `tests/test_database_migrations_manager.py`:
     - `create`, `status`, `up`, `down` の E2E シナリオ検証。
     - 部分適用（`steps` オプション）の動作検証。
     - `.down.sql` 欠損時の `MigrationFileNotFoundError` 検知。
     - PyDB（Primary）および SQLite（Secondary）双方での等価性検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/database/migrations/models.py` に `MigrationError`, `MigrationExecutionError`, `MigrationFileNotFoundError` が定義されていること。
- [x] `src/database/migrations/runner.py` および `manager.py` が新規作成されていること。
- [x] 第一優先の自作DB（`pydb`）および第二優先のSQLite（`sqlite`）の双方で、`up` / `down` / `status` / `create` が透過的に実行可能であること。
- [x] 自作DBおよびSQLiteの双方において、途中で意図的な SQL エラーを混入させた際に変更が 100% ロールバックされテーブルが作成されないことがテストで証明されていること。
- [x] テストカバレッジが 95% 以上を達成していること。
- [x] `mypy --strict src/database/migrations/` がエラー 0 件で通過すること。
- [x] `flake8 src/database/migrations/ tests/test_database_migrations*` がエラー 0 件で通過すること。
- [x] 全単体テストが PASS すること。
