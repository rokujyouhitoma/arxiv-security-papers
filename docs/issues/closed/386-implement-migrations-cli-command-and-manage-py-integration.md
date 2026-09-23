---
ID: 386
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 自己完結型 CLI コマンド＆manage.py統合の実装 (Phase 3) (ID: 386)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、高凝集な設計としてマイグレーションサブシステム内に自己完結する CLI コマンドハンドラ（`MigrationsCommand`）を実装し、`src/cli/registry.py` を介して `src/cli.py` およびルートの `manage.py` から統一的に呼び出し可能にする。
既定（デフォルト）として第一優先の自作DB（`--backend=pydb`）をターゲットとしつつ、第二優先として正式対応する SQLite（`--backend=sqlite`）の運用操作もシームレスに切り替えて実行できる CLI インターフェースを提供する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第2章、第7章、第11.2節 (Phase 3)
- 関連設計書: [DSN-24 統合管理 CLI (manage.py) および対話型データベースシェル (dbshell) 基本設計書](docs/designs/DSN-24-unified_management_cli_and_interactive_database_shell.md)
- 依存 Issue: [Issue #385](docs/issues/385-implement-atomic-migration-runner-and-manager-orchestrator.md) (Phase 2: トランザクション実行器＆オーケストレータ)

---

## 3. セキュリティ分析 (STRIDE 脅威モデリング) / Security Threat Analysis

本機能は CLI 引数解釈およびマイグレーションの直接実行を行うため、STRIDE 脅威モデリングを実施し防御策を組み込む。

| 脅威分類 (STRIDE) | 潜在リスク (Threat Scenario) | 緩和策・実装仕様 (Mitigation & Enforcement) |
| :--- | :--- | :--- |
| **Spoofing (なりすまし)** | 不正なバックエンド指定による意図しないDB操作 | `--backend` 引数を `choices=["pydb", "sqlite"]` で厳格制限し、`BackendType` Enum による型安全な検証を行う。 |
| **Tampering (改ざん)** | パストラバーサル (`../`) による不正なディレクトリ走査やマイグレーション作成 | `MigrationManager` のスネークケースバリデーションおよび `Path.resolve()` によるパス正規化を徹底し、ディレクトリ境界外への不正書き込みを防止する。 |
| **Repudiation (否認)** | マイグレーション実行履歴・結果の追跡不全 | 実行されたバージョン、適用時刻、対象バックエンド（Primary / Secondary）を標準出力および `schema_migrations` システムテーブルへ正確に記録する。 |
| **Information Disclosure (情報漏洩)** | 構文エラーや例外発生時の過剰なスタックトレース露出 | `MigrationError` 捕捉時に分かりやすい `[ERROR]` メッセージを出力し、機密情報の漏洩を防ぎつつ適切な終了コード（1）を返却する。 |
| **Denial of Service (DoS)** | マイグレーション途中の異常終了によるDBロック・不整合 | `MigrationRunner` のアトミックトランザクション境界（自動ロールバック）により、DBの排他ロック残留や中途半端なスキーマ破損を防止する。 |
| **Elevation of Privilege (権限昇格)** | 管理者権限を偽装した不正DDL投入 | OS のファイルシステム権限に基づき、指定 DB パスへの書き込み権限を前提として動作させる。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/migrations/cli.py](file:///workspace/arxiv-security-papers/src/database/migrations/cli.py) (新規: `MigrationsCommand(BaseCommand)`)
- [x] [src/database/migrations/__init__.py](file:///workspace/arxiv-security-papers/src/database/migrations/__init__.py) (`MigrationsCommand` のエクスポート)
- [x] [src/cli/registry.py](file:///workspace/arxiv-security-papers/src/cli/registry.py) (遅延ローダー `_load_migrations` 登録)
- [x] [src/cli.py](file:///workspace/arxiv-security-papers/src/cli.py) (新規: DSN-30 Section 7.2 準拠 CLI エントリポイント)
- [x] [tests/test_database_migrations_cli.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_cli.py) (新規: CLI 単体＆統合テスト)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/386-implement-migrations-cli-command-and-manage-py-integration`

1. **CLI ハンドラ実装 (`src/database/migrations/cli.py`)**:
   - `src/cli/base.py` の `BaseCommand` を継承した `MigrationsCommand` を作成。
   - `name = "migrations"`, `help_text = "Database schema migration management (DSN-30)"` を定義。
   - グローバル引数 `--backend`（`pydb` [既定・Primary] / `sqlite` [Secondary]）、サブコマンド用引数 `--db-path`、`--migrations-dir` をサポート。
   - サブコマンド（`create`, `up`, `down`, `status`）のパーサー構築。
   - Xenon CC <= 5 (Grade A) を維持するため、各サブコマンド処理を個別のハンドラメソッド（`_handle_create`, `_handle_up`, `_handle_down`, `_handle_status`）に分割。
   - ASCII 罫線テーブル形式によるステータス一覧描画（対象バックエンド明示、適用状況、バージョン、ファイル名、適用日時、集計行）。
2. **公開 API エクスポート (`src/database/migrations/__init__.py`)**:
   - `MigrationsCommand` を `__all__` に追加。
3. **CLI レジストリ登録 (`src/cli/registry.py`)**:
   - 遅延ローダー `_load_migrations()` を実装し、`_ensure_builtins()` 内で `migrations` サブコマンドとして登録。
4. **CLI エントリポイント実装 (`src/cli.py`)**:
   - DSN-30 Section 7.2 に準拠し、`CommandDispatcher` を呼び出す軽量エントリポイントを作成。
5. **CLI 単体・統合テスト (`tests/test_database_migrations_cli.py`)**:
   - `create`: 正常系（.up.sql / .down.sql 生成確認）、異常系（不正な名称）。
   - `up`: 差分適用、適用済みなし時のメッセージ出力。
   - `down`: 1ステップロールバック、ロールバック対象なし時の出力。
   - `status`: テーブル出力内容（バックエンド名、バージョン、ステータス）の検証。
   - デュアルバックエンド切替: `--backend=pydb`（既定）および `--backend=sqlite`。
   - 終了コード: 正常時 0、エラー発生時 1。
   - `manage.py` および `src/cli.py` 経由のディスパッチ統合テスト。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `src/database/migrations/cli.py` が実装され、`MigrationsCommand` が提供されていること。
- [x] Xenon 循環的複雑度検査（`--max-absolute A`）を全関数・メソッドでパスすること。
- [x] `src/cli/registry.py` に `migrations` コマンドが登録され、`manage.py` および `src/cli.py` から利用可能であること。
- [x] `src/cli.py` が DSN-30 Section 7.2 準拠で配置され、正常にディスパッチ動作すること。
- [x] 既定の自作DB（`--backend=pydb`）および正式対応のSQLite（`--backend=sqlite`）の双方が CLI から正常に実運用できること。
- [x] `status` コマンドの出力ヘッダに対象バックエンド名が明示され、ASCII テーブル形式で表示されること。
- [x] `pytest tests/test_database_migrations_cli.py` が全件 PASS すること。
- [x] `mypy --strict src/database/migrations/` および `src/cli/` がエラー 0 件で通過すること。
- [x] カバレッジ >= 90% を維持すること。
- [x] 本 Issue をクローズし、`docs/issues/closed/` に移管の上、台帳を更新すること。
