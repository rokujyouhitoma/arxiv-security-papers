---
ID: 291
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] SQL Parser 全面 Packrat PEG 換装 (DDL / TCL / DCL / Admin) による手書き正規表現コード完全撤廃 (ID: 291)

## 1. 概要 / Summary
[DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.4 節 Phase 2-D) に基づき、`src/database/sql/parser.py` に残存していた手書き正規表現・スキャナ実装（DDL, TCL, DCL, Admin/Utility 構文）を Packrat PEG パーサーエンジン（`src/core/structures/peg.py`）へ完全に移植・換装した。
これにより、`src/database/sql/parser.py` から旧正規表現解析コード（2,000行超）を全廃し、式（`expr_parser.py`）、DQL（`dql_parser.py`）、DML（`dml_parser.py`）、DDL/Admin（`ddl_parser.py`, `admin_parser.py`）をすべて Packrat PEG 統合文法として統一した。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.4 節)
- 設計書: [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
- 前提成果物:
  - [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)
  - [src/database/sql/expr_parser.py](../../src/database/sql/expr_parser.py) (Issue 288)
  - [src/database/sql/dql_parser.py](../../src/database/sql/dql_parser.py) (Issue 289)
  - [src/database/sql/dml_parser.py](../../src/database/sql/dml_parser.py) (Issue 290)
- 出力 AST: [src/database/sql/ast.py](../../src/database/sql/ast.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ddl_parser.py](../../src/database/sql/ddl_parser.py) (新規: DDL Packrat PEG パーサー)
- [x] [src/database/sql/admin_parser.py](../../src/database/sql/admin_parser.py) (新規: TCL / DCL / Admin Packrat PEG パーサー)
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py) (旧正規表現ロジック全廃・Packrat PEG 統合ディスパッチャーへの換装)
- [x] [src/database/sql/__init__.py](../../src/database/sql/__init__.py) (公開エクスポートの整理: `SQLDDLParser`, `SQLAdminParser`, `parse_ddl`, `parse_admin`, `parse_sql`)
- [x] [tests/database/test_sql_ddl_peg.py](../../tests/database/test_sql_ddl_peg.py) (新規: DDL/Admin PEG 網羅テスト)
- [x] [docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (設計書更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/291-replace-sql-parser-with-packrat-peg`

1. **DDL パーサーの構築 (`src/database/sql/ddl_parser.py`)**:
   - `CreateTableStatement`: 列定義、データ型、制約 (PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, COLLATE, GENERATED ALWAYS AS, FOREIGN KEY REFERENCES)、テーブル制約、STRICT
   - `CreateVirtualTableStatement`: USING module(args)
   - `CreateViewStatement`: AS DQL-SELECT
   - `CreateTriggerStatement`: BEFORE/AFTER/INSTEAD OF, INSERT/UPDATE/DELETE, WHEN cond, BEGIN ... END
   - `CreateIndexStatement`: UNIQUE, ON tbl (col ASC/DESC, ...), WHERE cond
   - `AlterTableStatement`: RENAME TO, RENAME COLUMN, ADD COLUMN, DROP COLUMN
   - `DropTableStatement`, `DropIndexStatement`, `DropViewStatement`, `DropTriggerStatement`
   - `ReindexStatement`

2. **Admin / TCL / DCL パーサーの構築 (`src/database/sql/admin_parser.py`)**:
   - TCL: `BEGIN [DEFERRED|IMMEDIATE|EXCLUSIVE] [TRANSACTION]`, `COMMIT [TRANSACTION]`, `ROLLBACK [TRANSACTION] [TO [SAVEPOINT] sp]`, `SAVEPOINT sp`, `RELEASE [SAVEPOINT] sp`
   - DCL: `GRANT ... TO ...`, `REVOKE ... FROM ...`
   - Admin/Utility: `PRAGMA ...`, `VACUUM ... [INTO ...]`, `ANALYZE ...`, `ATTACH ... AS ...`, `DETACH ...`, `EXPLAIN [QUERY PLAN] ...`, `SHOW ...`

3. **`SQLParser` の全面 Packrat PEG 統合ディスパッチャー化 (`src/database/sql/parser.py`)**:
   - `SQLParser.parse(sql)` を、先頭キーワードに応じた PEG パーサー分岐（または統合 Grammar.choice）に換装。
   - `parser.py` 内の手書き正規表現ヘルパー（1,000行超）を廃止・クリーンアップ。

4. **品質管理**:
   - Xenon CC Rank A ($CC \le 4$)
   - `mypy --strict` 準拠
   - 全 400 件のデータベーステストが 100% 成功

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ddl_parser.py` および `admin_parser.py` が Packrat PEG により正しく実装されていること
- [x] `parser.py` 内の手書き正規表現スキャナが Packrat PEG パーサーに完全に置き換えられていること
- [x] 全 382 件の既存データベーステストスイートが 100% PASS すること
- [x] 新規 `tests/database/test_sql_ddl_peg.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
- [x] `DSN-25` が最新状態に更新されていること
