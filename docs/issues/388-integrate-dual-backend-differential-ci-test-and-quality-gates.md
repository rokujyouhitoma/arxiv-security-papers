---
ID: 388
種別: Quality
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] デュアルバックエンド差分CIテスト＆品質ゲート統合 (Phase 5) (ID: 388)

## 1. 概要 / Summary

[DSN-30](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) に基づき、Makefile および CI/CD パイプライン（GitHub Actions）にマイグレーション検証ターゲットを統合する。第一優先の自作DB（`pydb`）および第二優先として正式対応する SQLite（`sqlite`）の双方で全マイグレーションを適用し、両者のスキーマ構造（テーブル一覧、カラム定義、型、インデックス）が 100% 一致することを自動監査する「差分テスト（Differential Test）」ステップを確立し、マルチデータベース運用品質を恒久的に保証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書: [DSN-30 データベースマイグレーションエンジン及びスキーマライフサイクルガバナンス基本設計書](docs/designs/DSN-30-database_migration_engine_and_schema_lifecycle_governance.md) 第1.2節、第10章、第11.2節 (Phase 5)
- 依存 Issue: [Issue #387](docs/issues/387-extract-baseline-ddl-and-purge-scattered-ddl-statements.md) (Phase 4: 現行DDLベースライン化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [Makefile](file:///workspace/arxiv-security-papers/Makefile)
- [ ] [.github/workflows/ci.yml](file:///workspace/arxiv-security-papers/.github/workflows/ci.yml)
- [ ] [tests/test_database_migrations_differential.py](file:///workspace/arxiv-security-papers/tests/test_database_migrations_differential.py)
- [ ] [docs/manuals/DEV-01-developer_manual.md](file:///workspace/arxiv-security-papers/docs/manuals/DEV-01-developer_manual.md)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `quality/388-dual-backend-differential-ci-test`

1. **Makefile ターゲット拡張**:
   - `migrations-up`: 第一優先の自作DBに対して全未適用マイグレーションを実行。
   - `migrations-up-sqlite`: 第二優先として正式対応する SQLite に対して全未適用マイグレーションを実行。
   - `migrations-status`: マイグレーション適用状況を表示（`--backend` 切り替え対応）。
   - `migrations-diff-test`: 自作DBとSQLiteの差分等価性テストを実行。
2. **デュアルバックエンド差分テスト (`tests/test_database_migrations_differential.py`)**:
   - 一時ディレクトリにクリーンな自作DBおよびSQLiteを作成。
   - `migrations/*.up.sql` を全件適用。
   - それぞれの DB メタデータインスペクタからテーブル名、カラム名、データ型、インデックス情報を抽出し、スキーマが完全一致することを検証（Assertion）。
   - `migrations/*.down.sql` を全件適用し、全テーブルが消去されるクリーンアップ等価性も検証。
3. **CI パイプライン統合**:
   - `.github/workflows/ci.yml` のテストジョブに `make migrations-diff-test` を追加し、PR 作成時に自動検証。
4. **開発者マニュアル（DEV-01）の更新**:
   - 自作DBを最優先としつつ SQLite にも完全対応するスキーマ変更ルール、新マイグレーション作成プロトコル、レビュー基準、ロールバックテスト手順をドキュメント化。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `Makefile` に `migrations-up`（自作DB）および `migrations-up-sqlite`（SQLite）、`migrations-status`、`migrations-diff-test` が定義され、実行可能であること。
- [ ] `tests/test_database_migrations_differential.py` が新規作成され、自作DBとSQLiteのスキーマ等価性が自動証明されること。
- [ ] CI パイプラインにおいて自作DBおよびSQLiteのマイグレーション・差分テストが実行され、PASS すること。
- [ ] 開発者マニュアル（`DEV-01`）に自作DB優先・SQLite正式対応のマイグレーション運用手順が明記されていること。
- [ ] プロジェクトの全品質ゲート（`make verify_quality` / `make check`）が 100% 通過すること。
