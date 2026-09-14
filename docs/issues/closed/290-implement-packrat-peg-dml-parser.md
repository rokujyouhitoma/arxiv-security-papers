---
ID: 290
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] DML (INSERT / UPDATE / DELETE / UPSERT / RETURNING) の Packrat PEG パーサー化 (ID: 290)

## 1. 概要 / Summary
[DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.3 節 Phase 2-C) に基づき、`src/database/sql/parser.py` 内で手書き正規表現・スキャナによって行われている DML（データ操作言語）の構文解析を、Packrat PEG エンジン（`src/core/structures/peg.py`, `src/database/sql/expr_parser.py`, `src/database/sql/dql_parser.py`）を用いて刷新する。

対象とする文法要素：
1. **INSERT / REPLACE 構文**:
   - `INSERT INTO [OR REPLACE | OR IGNORE | OR ABORT] tbl [(col1, col2, ...)] VALUES (v1_1, ...), (v2_1, ...) [RETURNING ...]`
   - `INSERT INTO tbl [(cols)] SELECT ...` (DQL サブクエリ連携)
   - `REPLACE INTO tbl [(cols)] VALUES (...)`
   - UPSERT 構文: `ON CONFLICT (col1, ...) [WHERE cond] DO UPDATE SET k1=v1, ... [WHERE cond]` / `DO NOTHING`
2. **UPDATE 構文**:
   - `UPDATE [OR ROLLBACK | OR ABORT | OR FAIL | OR IGNORE | OR REPLACE] tbl [AS alias] SET col1=expr1, col2=expr2, ... [FROM table2 [JOIN ...]] [WHERE cond] [RETURNING ...]`
   - `UPDATE ... FROM ...` (JOIN Update 構文)
3. **DELETE 構文**:
   - `DELETE FROM tbl [AS alias] [WHERE cond] [RETURNING ...]`
4. **RETURNING 句**:
   - `RETURNING *`, `RETURNING col1, col2 AS alias, ...`

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.3 節)
- 設計書: [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
- 前提成果物:
  - [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)
  - [src/database/sql/expr_parser.py](../../src/database/sql/expr_parser.py) (Issue 288)
  - [src/database/sql/dql_parser.py](../../src/database/sql/dql_parser.py) (Issue 289)
- 出力 AST: [src/database/sql/ast.py](../../src/database/sql/ast.py) (`InsertStatement`, `UpdateStatement`, `DeleteStatement`, `ConflictResolution`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/dml_parser.py](../../src/database/sql/dml_parser.py) (新規: Packrat PEG DML パーサー)
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py) (`_parse_insert`, `_parse_update`, `_parse_delete` の `dml_parser` への委譲)
- [x] [src/database/sql/__init__.py](../../src/database/sql/__init__.py) (公開エクスポートの追加: `SQLDMLParser`, `parse_dml`)
- [x] [tests/database/test_sql_dml_peg.py](../../tests/database/test_sql_dml_peg.py) (新規: DML PEG 網羅単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/290-packrat-peg-dml-parser`

1. **DML 文法ルールの定義 (`src/database/sql/dml_parser.py`)**:
   - `conflict_clause_p`: `OR (REPLACE | IGNORE | ABORT | FAIL | ROLLBACK)`
   - `returning_clause_p`: `RETURNING projection_list`
   - `upsert_clause_p`: `ON CONFLICT [(cols)] [WHERE expr] DO (NOTHING | UPDATE SET assignments [WHERE expr])`
   - `insert_stmt_p`: `(INSERT [conflict] INTO | REPLACE INTO) tbl_name [(cols)] (VALUES rows | select_stmt) [upsert] [returning]`
   - `update_stmt_p`: `UPDATE [conflict] tbl_name [AS alias] SET assignments [FROM table_ref joins] [WHERE expr] [returning]`
   - `delete_stmt_p`: `DELETE FROM tbl_name [AS alias] [WHERE expr] [returning]`
2. **`ast.py` ノードへの直接マッピング**:
   - `InsertStatement`, `UpdateStatement`, `DeleteStatement` を正確に生成。
3. **`SQLParser` の DML メソッド差し替え**:
   - `_parse_insert`, `_parse_update`, `_parse_delete` を `dml_parser.parse_dml` 経由に配線。
4. **品質管理**:
   - Xenon CC Rank A ($CC \le 4$)
   - `mypy --strict` 準拠
   - 全 366 件の既存 DB テスト ＋ DML PEG テストが 100% 成功

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/database/sql/dml_parser.py` に Packrat PEG による DML 解析エンジンが実装されていること
- [x] INSERT (単行/複数行/SELECT/UPSERT/RETURNING)、UPDATE (SET/FROM/WHERE/RETURNING)、DELETE (WHERE/RETURNING) が AST にパースできること
- [x] `SQLParser` から透過的に DML パーサーが呼び出され、既存の SQL テスト全件が成功すること
- [x] `tests/database/test_sql_dml_peg.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
