---
ID: 388
種別: Quality
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] デュアルバックエンド差分CIテスト＆品質ゲート統合 (Phase 5) (ID: 388)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、Makefile および CI/CD パイプライン（GitHub Actions）にマイグレーション検証ターゲットを統合した。第一優先の自作DB（`pydb` / `src.database`）および第二優先として正式対応する SQLite（`sqlite` / `sqlite3`）の双方で全マイグレーションを走査・適用し、両者のスキーマ構造（テーブル一覧、カラム定義・型、インデックス情報）およびデータ操作（DML/クエリ）挙動が 100% 一致することを自動監査する「差分テスト（Differential Test）」ステップを確立し、マルチデータベース運用品質を恒久的に保証した。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](../designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第8章、第9.3節、第10章、第11.2節 (Phase 5)
- 依存 Issue:
  - [Issue #384](closed/384-implement-migration-models-and-dual-pep249-connection-adapter.md) (Phase 1: データモデル・PEP249デュアル接続アダプタ)
  - [Issue #385](closed/385-implement-atomic-migration-runner-and-manager-orchestrator.md) (Phase 2: トランザクション実行器＆MigrationManager)
  - [Issue #386](closed/386-implement-migrations-cli-command-and-manage-py-integration.md) (Phase 3: 自己完結型 CLI コマンド＆manage.py統合)
  - [Issue #387](closed/387-extract-baseline-ddl-and-purge-scattered-ddl-statements.md) (Phase 4: 現行DDLベースライン化＆散在DDL全廃)

---

## 3. セキュリティ・脅威分析 (STRIDE Threat Model)

| 脅威分類 | リスク要因 | 本実装における緩和策・防御方針 |
| :--- | :--- | :--- |
| **Spoofing (なりすまし)** | CIテスト環境での未検証・改ざんされたDB接続の偽装 | テスト時は `tmp_path` による独立サンドボックス内で明示的に生成されたDBファイルのみに接続し、外部リソース混入を防止。 |
| **Tampering (改ざん)** | マイグレーション実行時のスキーマ不整合・部分的適用 | 自作DB（ARIES WAL）および SQLite（排他トランザクション）でのアトミック実行と、差分テストによるテーブル・カラム・インデックスメタデータの完全一致自動照合。 |
| **Repudiation (否認)** | マイグレーション差分検出失敗時の追跡困難性 | 差分検出時に差異のあるテーブル名、カラム名、型定義、インデックス情報を詳細に出力・アサーションログに記録。 |
| **Information Disclosure (情報漏洩)** | テスト実行ログやCI出力への機密情報露出 | スキーマメタデータ構造の比較のみを行い、本番データ・認証情報を含めない。 |
| **Denial of Service (DoS)** | 差分比較時の無限ループやリソース枯渇 | メタデータ比較アルゴリズムをO(N)辞書照合とし、タイムアウトとクリーンアップを徹底。 |
| **Elevation of Privilege (権限昇格)** | 悪意ある DDL 文によるインジェクション | 正規表現 `MIGRATION_FILENAME_PATTERN` によるファイル名ホワイトリスト検証を通過したスクリプトのみを対象とする。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [Makefile](file:///workspace/arxiv-security-papers/Makefile)
- [x] [.github/workflows/ci.yml](file:///workspace/arxiv-security-papers/.github/workflows/ci.yml)
- [x] [tests/test_database_migrations_differential.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_differential.py)
- [x] [docs/manuals/DEV-01-developer_manual.md](file:///workspace/arxiv-security-papers/docs/manuals/DEV-01-developer_manual.md)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `quality/388-dual-backend-differential-ci-test`

1. **Makefile ターゲット拡張**:
   - `migrations-up`: 第一優先の自作DBに対して全未適用マイグレーションを実行 (`python src/cli.py migrations up`)。
   - `migrations-up-sqlite`: 第二優先として正式対応する SQLite に対して全未適用マイグレーションを実行 (`python src/cli.py migrations up --backend sqlite`)。
   - `migrations-down`: 自作DBに対して直近マイグレーションをロールバック (`python src/cli.py migrations down`)。
   - `migrations-down-sqlite`: SQLite に対してロールバック (`python src/cli.py migrations down --backend sqlite`)。
   - `migrations-status`: マイグレーション適用状況を表示 (`python src/cli.py migrations status`)。
   - `migrations-create`: 新規マイグレーション雛形を生成 (`python src/cli.py migrations create $(NAME)`)。
   - `migrations-diff-test`: 自作DBとSQLiteの差分等価性テストを実行 (`pytest tests/test_database_migrations_differential.py`)。
   - `differential_audit`: 既存の差分検証ターゲットに `migrations-diff-test` の実行を追加統合。

2. **デュアルバックエンド差分テスト (`tests/test_database_migrations_differential.py`)**:
   - 一時ディレクトリにクリーンな自作DB (`.vdb`) および SQLite (`.db`) を初期化。
   - `MigrationManager` を介して `migrations/*.up.sql` を全件適用。
   - スキーマインスペクション比較:
     - テーブル一覧の完全一致 (`sqlite_master` 走査)。
     - 各テーブルのカラム構成（カラム名、データ型）の完全一致 (`PRAGMA table_info` 走査)。
     - インデックス構成（インデックス名、対象テーブル）の完全一致。
   - DML/クエリ挙動等価性:
     - 各テーブルへのレコード挿入および `SELECT` クエリ実行結果（行データ、カラム順）が両エンジンで完全同一であることを検証。
   - ロールバック (`down`) 等価性:
     - 両エンジンで `down` を実行し、全テーブル・インデックスが対称的かつ完全に消去されることを検証。
   - 再適用 (`up`) 冪等性:
     - ロールバック後に再度 `up` を実行し、スキーマが元通り完全一致で再構築されることを検証。
   - Xenon Grade A (循環的複雑度 CC <= 5) および strict mypy を徹底。

3. **CI/CD パイプライン定義 (`.github/workflows/ci.yml`)**:
   - GitHub Actions ワークフローを新規構築。
   - `ubuntu-24.04` 環境上で Python 3.14 をセットアップ。
   - 依存パッケージのキャッシュとインストール (`pip install -r requirements.txt`)。
   - 厳格品質ゲートの順次実行:
     - `make check_format`
     - `make static_analysis` (radon, xenon, mypy, py_compile)
     - `make test`
     - `make migrations-diff-test`
     - `make differential_audit`

4. **開発者マニュアル（`DEV-01`）の更新**:
   - 「データベースマイグレーション運用ガイド」セクションを新設。
   - 自作DB最優先 (`pydb`) と SQLite正式対応 (`sqlite`) のデュアルバックエンド原則。
   - マイグレーション操作コマンド（`make migrations-*`, `manage.py migrations ...`）一覧。
   - スキーマ変更規約（DDL構文互換性、破壊的変更時のテーブル再作成標準パターン）。
   - 差分テスト (`make migrations-diff-test`) によるレビュー・品質保証プロトコル。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `Makefile` に `migrations-up`、`migrations-up-sqlite`、`migrations-down`、`migrations-down-sqlite`、`migrations-status`、`migrations-create`、`migrations-diff-test` が定義され、エラーなく実行可能であること。
- [x] `tests/test_database_migrations_differential.py` が作成され、自作DBとSQLiteにおけるスキーマ構造・DML・ロールバックの完全等価性が自動テストで証明されること。
- [x] `.github/workflows/ci.yml` が新規作成され、`make migrations-diff-test` および一連の品質ゲートが定義されていること。
- [x] 開発者マニュアル（`docs/manuals/DEV-01-developer_manual.md`）にデュアルバックエンドマイグレーション運用手順が明記されていること。
- [x] プロジェクトの全品質ゲート（`make check_format`, `xenon --max-absolute A`, `mypy --strict`, `pytest`）が 100% 通過すること。
- [x] Issue #388 が完了し、クローズ台帳へ記録されること。
