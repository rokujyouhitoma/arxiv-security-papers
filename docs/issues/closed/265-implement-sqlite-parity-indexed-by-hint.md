---
ID: 265
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: INDEXED BY / NOT INDEXED 句による明示的インデックスヒントの実装 (ID: 265)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_indexedby.html](https://sqlite.org/lang_indexedby.html)) に準拠した `INDEXED BY index_name` および `NOT INDEXED` 句を Pure Python SQL Engine (`src/database/sql/`) に実装する。
現在、クエリオプティマイザ（`CBOptimizer` / ルールベース）は WHERE 条件に基づいて自動的に使用するインデックスを決定するが、`FROM table_name INDEXED BY index_name` を指定することで特定のインデックス走査を強制し、`FROM table_name NOT INDEXED` を指定することでインデックスの使用を明示的に禁止してフルテーブルスキャンを強制できるようにする。
また、指定されたインデックスが存在しない場合や、クエリ条件に適合せず走査不可能な場合には SQLite 互換のエラーを発生させる。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite INDEXED BY](https://sqlite.org/lang_indexedby.html)
- 関連設計書: 
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `TableRef` クラスへの `indexed_by: Optional[str]` および `not_indexed: bool` 属性追加
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py): `FROM` 句および `JOIN` 句における `INDEXED BY index_name` / `NOT INDEXED` のパース
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): クエリ実行エンジンにおけるインデックス選択ヒントの反映
- [x] [src/database/planner/planner.py](../../src/database/planner/planner.py): オプティマイザのインデックス決定ロジックへの強制・禁止ルール適用
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): INDEXED BY / NOT INDEXED 実行および EXPLAIN 検証テスト
- [x] [docs/issues/README.md](../README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/265-implement-sqlite-parity-indexed-by-hint`

1. **AST & Parser 実装**:
   - `TableRef` に `indexed_by: Optional[str] = None`, `not_indexed: bool = False` を追加。
   - `parser.py` のテーブル参照解析部分で、テーブル名（およびエイリアス）の後に `INDEXED BY <ident>` または `NOT INDEXED` を認識。
2. **オプティマイザ & 実行エンジン連携 (`src/database/sql/executor.py`)**:
   - `not_indexed` が True の場合、インデックス走査をスキップし常にストレージのフルスキャンを選択。
   - `indexed_by` が指定されている場合:
     - テーブルに当該インデックスが存在するか検証（存在しなければエラー）。
     - 当該インデックスを強制使用してレコードポインタを取得。
3. **EXPLAIN / EXPLAIN QUERY PLAN 連携**:
   - `EXPLAIN QUERY PLAN` の出力で、指定されたインデックス走査（`SCAN ... USING INDEX <idx>`）またはフルスキャン（`SCAN ...`）が正しく表示されることを確認。
4. **品質規律**:
   - No-eval 原則厳守、Xenon CC Rank A ($\le 5$)、Mypy strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `SELECT * FROM tbl INDEXED BY idx_col WHERE ...` が指定されたインデックスを用いて実行されること。
- [x] `SELECT * FROM tbl NOT INDEXED WHERE ...` がインデックスを使用せずフルスキャンで実行されること。
- [x] 存在しないインデックスを `INDEXED BY` で指定した場合に適切なエラーが発生すること。
- [x] `EXPLAIN QUERY PLAN` で意図した走査方式が反映されていること。
- [x] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [x] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
