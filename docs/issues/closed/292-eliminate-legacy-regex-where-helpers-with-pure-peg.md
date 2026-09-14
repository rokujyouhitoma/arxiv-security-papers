---
ID: 292
種別: Refactoring
優先度: High
ステータス: Closed
---

# [REFACTOR] SQL Parser 残存手書き正規表現・文字列走査ロジックの完全撤廃と純粋 PEG 化 (ID: 292)

## 1. 概要 / Summary
[DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) に基づき、`src/database/sql/parser.py` に残存していた手書き正規表現述語パーサー群（`_parse_cmp_clause`, `_parse_between_clause`, `_parse_like_clause`, `_parse_in_clause`, `_parse_exists_clause` 等 約 150 行）、手書き文字走査ループによるカンマ分割（`_split_comma_expressions`）、および `__BETWEEN_AND__` 文字列置換ハックを完全に撤廃した。
これらをすべて `SQLExpressionParser`（Packrat PEG）と PEG コンビネータによる構文木抽出に置き換え、`src/database/sql/parser.py` から `import re` を完全に追放して 100% 純粋な Packrat PEG 統合ディスパッチャーを完成させた。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 設計書: [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
- 前提成果物:
  - [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)
  - [src/database/sql/expr_parser.py](../../src/database/sql/expr_parser.py) (Issue 288)
  - [src/database/sql/dql_parser.py](../../src/database/sql/dql_parser.py) (Issue 289)
  - [src/database/sql/dml_parser.py](../../src/database/sql/dml_parser.py) (Issue 290)
  - [src/database/sql/ddl_parser.py](../../src/database/sql/ddl_parser.py) (Issue 291)
  - [src/database/sql/admin_parser.py](../../src/database/sql/admin_parser.py) (Issue 291)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py) (`import re` 撤廃、正規表現 WHERE パーサー全廃、PEG ベースの WHERE/カンマ解析への置換)
- [x] [src/database/sql/expr_parser.py](../../src/database/sql/expr_parser.py) (COLLATE 句、EXISTS サブクエリ、負数定数評価 `_eval_constant`、IN サブクエリの PEG 化)
- [x] [tests/database/test_sql_expr_peg.py](../../tests/database/test_sql_expr_peg.py) (COLLATE, EXISTS の単体テスト追加)
- [x] [docs/issues/README.md](../issues/README.md) (Issue 台帳更新)
- [x] [docs/designs/DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (設計書追記)

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] `src/database/sql/parser.py` から `import re` が完全撤廃されていること
- [x] 手書き正規表現 `_WHERE_PARSERS` 群がすべて削除され、`SQLExpressionParser` (PEG) による構文木解析に置き換わっていること
- [x] `_split_comma_expressions` が PEG ベースに置き換えられていること
- [x] データベーステスト全 401 件が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
