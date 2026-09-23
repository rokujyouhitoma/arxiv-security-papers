---
ID: 386
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 自己完結型 CLI コマンド＆manage.py統合の実装 (Phase 3) (ID: 386)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、高凝集な設計としてマイグレーションサブシステム内に自己完結する CLI コマンドハンドラ（`MigrationsCommand`）を実装し、`src/cli/registry.py` を介して `src/cli.py` およびルートの `manage.py` から統一的に呼び出し可能にする。
既定（デフォルト）として第一優先の自作DB（`--backend=pydb`）をターゲットとしつつ、第二優先として正式対応する SQLite（`--backend=sqlite`）の運用操作もシームレスに切り替えて実行できる CLI インターフェースを提供する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第2章、第7章、第11.2節 (Phase 3)
- 依存 Issue: [Issue #385](docs/issues/385-implement-atomic-migration-runner-and-manager-orchestrator.md) (Phase 2: トランザクション実行器＆オーケストレータ)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [src/database/migrations/cli.py](file:///workspace/arxiv-security-papers/src/database/migrations/cli.py)
- [ ] [src/cli/registry.py](file:///workspace/arxiv-security-papers/src/cli/registry.py)
- [ ] [src/cli.py](file:///workspace/arxiv-security-papers/src/cli.py)
- [ ] [manage.py](file:///workspace/arxiv-security-papers/manage.py)
- [ ] [tests/test_database_migrations_cli.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_cli.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/386-migrations-cli-and-manage-py-integration`

1. **CLI ハンドラ実装 (`src/database/migrations/cli.py`)**:
   - `argparse` サブパーサー構築（`create`, `up`, `down`, `status`）。
   - コマンドライン引数 `--backend`（`pydb` [第一優先・既定] / `sqlite` [第二優先・正式対応]）、`--db-path`、`--dir`、`--steps`、`--yes` 等のオプションサポート。
   - 美麗な ASCII 罫線テーブル形式によるステータス一覧描画（対象バックエンド明示、適用状況、バージョン、ファイル名、適用日時、所要時間）。
2. **CLI レジストリ登録 (`src/cli/registry.py`)**:
   - `MigrationsCommand` をレジストリに登録し、`src/cli.py` から遅延インポート可能にする。
3. **エントリポイント統合検証**:
   - `python src/cli.py migrations status`
   - `python manage.py migrations status`
   - 上記いずれの経路からも同一の CLI ハンドラが透過的に呼び出されることを確認。
4. **CLI 単体・統合テスト (`tests/test_database_migrations_cli.py`)**:
   - 自作DB（既定）および SQLite 指定時のコマンドライン実行、stdout / stderr 出力、終了コード、引数バリデーションをテストする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/migrations/cli.py` が実装され、`MigrationsCommand` が提供されていること。
- [ ] `src/cli/registry.py` に `migrations` コマンドが登録され、`manage.py` および `src/cli.py` から利用可能であること。
- [ ] 既定の自作DB（`--backend=pydb`）および正式対応のSQLite（`--backend=sqlite`）の双方が CLI から正常に実運用できること。
- [ ] `status` コマンドの出力ヘッダに対象バックエンド名が明示され、ASCII テーブル形式で表示されること。
- [ ] `pytest tests/test_database_migrations_cli.py` が全件 PASS すること。
- [ ] `mypy --strict src/database/migrations/cli.py src/cli/registry.py` がエラー 0 件で通過すること。
