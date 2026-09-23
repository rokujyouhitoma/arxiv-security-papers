---
ID: 385
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] トランザクション実行器＆MigrationManagerオーケストレータの実装 (Phase 2) (ID: 385)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、マイグレーションSQLスクリプトをアトミックに適用・記録するトランザクション実行器（`MigrationRunner`）および、`create`, `up`, `down`, `status` コマンドのコア業務ロジックを統合統制する `MigrationManager` オーケストレータを実装する。
優先度として自作DB（`src/database/`）での実行を最優先標準（既定値）としつつ、SQLite（`sqlite3`）環境でも同一ロジック・同一信頼性で動作するマルチデータベース対応エンジンを構築する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第6章、第7章、第11.2節 (Phase 2)
- 依存 Issue: [Issue #384](docs/issues/384-implement-migration-models-and-dual-pep249-connection-adapter.md) (Phase 1: データモデル・接続アダプタ)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/database/migrations/runner.py](file:///workspace/arxiv-security-papers/src/database/migrations/runner.py)
- [ ] [src/database/migrations/manager.py](file:///workspace/arxiv-security-papers/src/database/migrations/manager.py)
- [ ] [tests/test_database_migrations_runner.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_runner.py)
- [ ] [tests/test_database_migrations_manager.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_manager.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/385-atomic-migration-runner-and-manager`

1. **アトミック実行器 (`runner.py`)**:
   - 単一トランザクション内での複数 SQL ステートメント（分流・セミコロン分割）の逐次実行ロジック。
   - 第一優先の自作DBにおける ARIES WAL フラッシュ同期保証およびロールバック時の SlottedPage バッファ保護。
   - 第二優先の SQLite における排他トランザクション（`BEGIN EXCLUSIVE`）およびロールバック制御。
   - `schema_migrations` への適用レコード追記（`applied_at` UTCタイムスタンプ・適用所要ミリ秒）または削除処理。
2. **コアオーケストレータ (`manager.py`)**:
   - `create(name: str)`: 14桁UTCタイムスタンププレフィックスを付与した `.up.sql` / `.down.sql` 雛形ファイルの自動生成。
   - `up(steps: Optional[int])`: 未適用マイグレーションの検出、順序ソート、逐次適用。
   - `down(steps: int = 1)`: 直近適用済みマイグレーションの逆順走査、`.down.sql` の実行と台帳レコード削除。
   - `status()`: ローカルファイルと DB 台帳の突き合わせ、適用状況（`APPLIED` / `PENDING`）の構造化データ返却。
3. **包括的テストスイート**:
   - 第一優先の自作DB、および第二優先のSQLiteの双方における複数段マイグレーションの逐次適用と巻き戻し検証。
   - DDL 途中で構文エラーが発生した際の完全自動ロールバックと DB ファイル整合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/migrations/runner.py` および `manager.py` が新規作成されていること。
- [ ] 第一優先の自作DB（`pydb`）および第二優先のSQLite（`sqlite`）の双方で、`up` / `down` / `status` / `create` が透過的に実行可能であること。
- [ ] 自作DBおよびSQLiteの双方において、途中で意図的な SQL エラーを混入させた際に変更が 100% ロールバックされテーブルが作成されないことがテストで証明されていること。
- [ ] テストカバレッジが 95% 以上を達成していること。
- [ ] `mypy --strict src/database/migrations/` がエラー 0 件で通過すること。
