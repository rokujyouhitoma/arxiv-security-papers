---
ID: 262
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: ANALYZE 構文による統計情報収集と CBO 最適化連携の実装 (ID: 262)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_analyze.html](https://sqlite.org/lang_analyze.html)) に準拠した `ANALYZE` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
`ANALYZE [database | table | index]` を実行することで、指定されたテーブルやインデックスの全件走査を行い、行数、カラム別カーディナリティ（個別値数）、NULL値比率、最小・最大値、インデックス分布統計を収集する。
収集した統計情報は内部メタデータ（`sqlite_stat1` 互換テーブルまたは CBO カタログ）に記録・更新し、`src/database/planner/cbo.py` のコストベースオプティマイザ（CBO）が最新の統計情報に基づいて最適な実行計画（インデックス選択、結合順序、走査戦略）を決定できるようにする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite ANALYZE](https://sqlite.org/lang_analyze.html)
- 関連設計書: 
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `AnalyzeStatement` AST クラスの追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `ANALYZE` 文のパース処理（対象名省略、テーブル名指定、インデックス名指定）
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `_exec_analyze` ハンドラおよび統計走査エンジンの実装
- [ ] [src/database/planner/cbo.py](../../src/database/planner/cbo.py): `ANALYZE` 統計情報と CBO コスト計算の連携
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): `ANALYZE` 実行および統計更新の単体テスト
- [ ] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/262-implement-sqlite-parity-analyze-statement`

1. **AST & Parser 実装**:
   - `AnalyzeStatement(SQLStatement)` を追加（`target_name: Optional[str]`, `schema_name: Optional[str]`）。
   - `parser.py` に `_parse_analyze` を追加し、`ANALYZE`, `ANALYZE tbl`, `ANALYZE schema.tbl` を解析。
2. **統計収集エンジン (`src/database/sql/executor.py`)**:
   - テーブル対象走査: 総レコード数、各列の NULL 数、ユニーク値数（HyperLogLog / Set）を算出。
   - インデックス対象走査: インデックス付きキーの分布をサンプリング。
   - `sqlite_stat1` 互換の統計メタデータ辞書へ格納。
3. **CBO 連携 (`src/database/planner/cbo.py`)**:
   - `CBOptimizer` が利用するテーブル統計を `ANALYZE` で更新された最新値で更新。
4. **品質規律**:
   - No-eval 原則厳守、Xenon CC Rank A ($\le 5$)、Mypy strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ANALYZE`、`ANALYZE table_name` がエラーなく実行され、影響行数または完了ステータスが返却されること。
- [ ] `ANALYZE` 実行後にテーブル統計（行数、カーディナリティ等）が正しく更新されること。
- [ ] CBO 最適化が収集された統計情報を参照できること。
- [ ] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [ ] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
