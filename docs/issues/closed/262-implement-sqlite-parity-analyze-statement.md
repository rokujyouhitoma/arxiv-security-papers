---
ID: 262
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: ANALYZE 構文による統計情報収集と CBO 最適化連携の実装 (ID: 262)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_analyze.html](https://sqlite.org/lang_analyze.html)) に準拠した `ANALYZE` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
`ANALYZE [database | table | index]` を実行することで、指定されたテーブルやインデックスの全件走査を行い、行数、カラム別カーディナリティ（個別値数）、NULL値比率、最小・最大値、インデックス分布統計を収集する。
収集した統計情報は内部メタデータ（`TableStats` / `ColumnStats`）に記録・更新し、`src/database/planner/planner.py` のコストベースオプティマイザ（`QueryPlanner` / CBO）が最新の統計情報に基づいて最適な実行計画（インデックス選択、走査戦略、選択度見積もり）を決定できるようにする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite ANALYZE](https://sqlite.org/lang_analyze.html)
- 関連設計書: 
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `AnalyzeStatement` AST クラスの追加 (`target_name: Optional[str]`, `schema_name: Optional[str]`)
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py): `ANALYZE` 文のパース処理（対象名省略、テーブル名指定、スキーマ修飾テーブル名指定）
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): `_exec_analyze` ハンドラの実装（`TableMetadata.recompute_stats()` の実行および統計サマリー返却）
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): `ANALYZE` 実行および統計更新の単体テスト
- [x] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/262-implement-sqlite-parity-analyze-statement`

1. **AST & Parser 実装**:
   - `src/database/sql/ast.py` に `SQLCommandType.ANALYZE = "ANALYZE"` を追加し、`AnalyzeStatement(SQLStatement)` を実装。
   - `src/database/sql/parser.py` に `_parse_analyze` を実装し、`ANALYZE`, `ANALYZE tbl`, `ANALYZE schema.tbl` をトークン分解。
   - `SQLParser.parse` のディスパッチテーブルに `ANALYZE` を追加。
2. **Executor 連携 (`src/database/sql/executor.py`)**:
   - `_exec_analyze` を実装:
     - `target_name` が None の場合: カタログ内の全テーブルに対して `recompute_stats()` を呼び出し、全テーブルの行数・列統計を更新。
     - `target_name` が指定された場合: 当該テーブル（またはインデックスの親テーブル）に対して `recompute_stats()` を実行。
     - 存在しないテーブル名が指定された場合は `TableNotFoundError` または SQLite 互換の適切なエラーをハンドリング。
   - 返却結果: 分析対象テーブル数、総分析行数、各カラムのカーディナリティサマリー。
3. **CBO / QueryPlanner 連携検証**:
   - `TableMetadata.stats`（`TableStats`）が正しく更新され、`QueryPlanner.plan_query` 実行時に最新の選択度が使われることを単体テストで検証。
4. **セキュリティ & 品質規律**:
   - No-eval 原則厳守、Xenon CC Rank A ($\le 5$)、Mypy strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ANALYZE`（全体）および `ANALYZE table_name`（個別テーブル）が正常実行されること。
- [x] `ANALYZE` 実行後に `table.stats.total_rows` および `columns` の統計情報が実データと整合していること。
- [x] `QueryPlanner.explain` で `ANALYZE` 後の統計情報が推定コストに反映されること。
- [x] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [x] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。

