---
ID: 387
種別: Refactor
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 現行DDLベースライン化＆散在DDL全廃リファクタリング (Phase 4) (ID: 387)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、現在システム各所（データアクセス層、リポジトリ、初期化スクリプト等）に散在している `CREATE TABLE` / `CREATE INDEX` 発行ロジックを完全抽出し、第一優先の自作DB（`src/database/`）および第二優先として正式対応する SQLite（`sqlite3`）の双方で完全互換となるベースラインマイグレーション `migrations/20260923000000_baseline.up.sql` として一本化する。同時に、アプリケーションコード内の散在 DDL 発行コードを全廃し、DB スキーマ初期化をマイグレーションエンジンへ完全移管する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第3章、第8章、第9章、第11.2節 (Phase 4)
- 依存 Issue: [Issue #386](docs/issues/386-implement-migrations-cli-command-and-manage-py-integration.md) (Phase 3: CLIコマンド＆管理統合)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [migrations/20260923000000_baseline.up.sql](file:///workspace/arxiv-security-papers/migrations/20260923000000_baseline.up.sql)
- [ ] [migrations/20260923000000_baseline.down.sql](file:///workspace/arxiv-security-papers/migrations/20260923000000_baseline.down.sql)
- [ ] [src/database/](file:///workspace/arxiv-security-papers/src/database/) (データアクセス層、テーブル初期化部)
- [ ] [src/pipeline/](file:///workspace/arxiv-security-papers/src/pipeline/) (パイプライン内DB初期化処理)
- [ ] [tests/test_database_migrations_baseline.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_baseline.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/387-baseline-ddl-and-purge-scattered-ddl`

1. **現行 DDL の完全棚卸しとベースライン作成**:
   - `papers`, `authors`, `categories`, `audit_logs`, `spider_executions` 等、システムで利用されている全テーブルおよびインデックスの定義を収集。
   - 自作DB（第一優先）および SQLite（第二優先）の双方で無修正実行可能な標準 DDL スクリプトとして `migrations/20260923000000_baseline.up.sql`（全テーブル・インデックス作成 DDL）および `migrations/20260923000000_baseline.down.sql`（DROP TABLE スクリプト）を作成。
2. **散在 DDL 発行コードの全廃**:
   - `src/` 配下の Python コードを grep 走査し、`CREATE TABLE IF NOT EXISTS` や `CREATE INDEX` を直接呼び出している箇所を特定。
   - スキーマ作成責務をコードから剥奪し、マイグレーション適用済みであることを前提とする構造へリファクタリング。
3. **既存稼働環境のベースライン化スクリプト**:
   - 既にテーブルが存在する既存 DB ファイルに対して、テーブルを再作成せず台帳に `20260923000000` を適用済みとして安全に登録する初期化手順・フラグ（`--fake` / 既存判定）の確認。
4. **新規環境構築 E2E 検証**:
   - 空の DB ファイルに対して `python manage.py migrations up` を実行し、全テーブル・インデックスが自作DB（既定）および SQLite（指定時）の双方に正しく構築され、システムが正常起動することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `migrations/20260923000000_baseline.up.sql` および `.down.sql` が正しく配置されていること。
- [ ] `src/` 配下にアドホックな DDL 発行コードが 1 件も残存していないこと（grep 検査で 0 件）。
- [ ] クリーンな新規環境において `python manage.py migrations up` を実行するだけで、第一優先の自作DB（`.vdb`）および第二優先のSQLite（`.db`）の双方で全スキーマが完全に構築されること。
- [ ] パイプライン実行および既存の全単体・統合テストが破損することなく正常に通過すること。
