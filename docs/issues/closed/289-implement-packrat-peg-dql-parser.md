---
ID: 289
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] DQL & 派生クエリ (SELECT / CTE / JOIN / SET / VALUES) の Packrat PEG パーサー化 (ID: 289)

## 1. 概要 / Summary
[DSN-25](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.2 節 Phase 2-B) に基づき、`src/database/sql/parser.py` 内で手書きスキャナ・正規表現によって行われている DQL（データ問い合わせ言語）の構文解析を、Packrat PEG エンジン（`src/core/structures/peg.py` および `src/database/sql/expr_parser.py`）を用いて刷新した。

対象とする文法要素：
- `SELECT` 射影リスト（`*`, `table.*`, 式、エイリアス `AS name` / `name`）
- `DISTINCT` / `ALL` 修飾子
- `FROM` 句（テーブル名、修飾テーブル名 `schema.table`、テーブルエイリアス、派生テーブル・サブクエリ `(SELECT ...) AS sub`、カンマ結合暗黙 CROSS JOIN）
- `JOIN` 構文（`INNER`, `LEFT [OUTER]`, `RIGHT`, `CROSS`, `NATURAL`, `JOIN ... ON cond`, `JOIN ... USING (col1, ...)`）
- `WHERE` 句（`SQLExpressionParser` および既存 WHERE パーサーとの完全統合、二項 KNN `col KNN vec TOP k` 対応）
- `GROUP BY` 句および `HAVING` 句
- `WINDOW` 句および集約関数の `OVER (PARTITION BY ... ORDER BY ...)` 構文
- 集合演算（`UNION [ALL]`, `INTERSECT`, `EXCEPT`）
- `ORDER BY` 句（複数キー対応、`COLLATE`, `ASC` / `DESC`, `NULLS FIRST` / `NULLS LAST`）
- `LIMIT` 句および `OFFSET` 句（`LIMIT n OFFSET m` / `LIMIT m, n`）
- CTE 共通テーブル式（`WITH [RECURSIVE] cte_name [(cols)] AS (SELECT ...)`）
- スタンドアロン `VALUES (r1_1, r1_2), (r2_1, r2_2)` クエリ

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第 5.2.2 節)
- 設計書: [DSN-05-database_engine_architecture.md](../../designs/DSN-05-database_engine_architecture.md)
- 前提成果物:
  - [src/core/structures/peg.py](../../../src/core/structures/peg.py) (Issue 284)
  - [src/database/sql/expr_parser.py](../../../src/database/sql/expr_parser.py) (Issue 288)
- 出力 AST: [src/database/sql/ast.py](../../../src/database/sql/ast.py) (`SelectStatement`, `TableRef`, `JoinClause`, `CTEDefinition`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/dql_parser.py](../../../src/database/sql/dql_parser.py) (新規: Packrat PEG DQL パーサー)
- [x] [src/database/sql/parser.py](../../../src/database/sql/parser.py) (`SQLParser._parse_select` / `_parse_cte` から `dql_parser` への完全委譲)
- [x] [src/database/sql/__init__.py](../../../src/database/sql/__init__.py) (公開エクスポートの追加)
- [x] [tests/database/test_sql_dql_peg.py](../../../tests/database/test_sql_dql_peg.py) (新規: DQL PEG 網羅テスト 21件)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/289-packrat-peg-dql-parser`

1. **DQL 文法ルールの定義 (`src/database/sql/dql_parser.py`)**:
   - `ident_p`: 識別子（プレーン識別子、修飾テーブル名、バッククォート/ダブルクォート識別子）
   - `_build_projection_item`: 列射影 (`*`, `table.*`, `expr [AS] alias`)
   - `_build_table_ref_parser`: テーブル名、TVF (`json_each`, `json_tree`)、サブクエリ `(select_ref) [AS] alias`、INDEXED BY / NOT INDEXED
   - `_build_join_clause_parser`: 明示的 JOIN (`ON`, `USING`) およびカンマ結合 (`FROM t1, t2`)
   - `where_clause`: `WHERE expr` (二項 KNN および既存 WHERE 句抽出パーサーとの完全統合)
   - `group_by_p`: `GROUP BY col1, col2 ...`
   - `having_p`: `HAVING cond`
   - `order_by_p`: `ORDER BY item1, item2 ...` (`COLLATE`, `ASC/DESC`, `NULLS`)
   - `limit_offset_p`: `LIMIT count OFFSET offset` または `LIMIT offset, count`
   - `single_select`: `SELECT [DISTINCT|ALL] ... FROM ... [JOIN ...] [WHERE ...] [GROUP BY ... [HAVING ...]]`
   - `compound_query`: `core ((UNION [ALL] | INTERSECT | EXCEPT) core)*`
   - `cte_p`: `WITH [RECURSIVE] name [(cols)] AS (compound) ... compound`
   - `values_p`: `VALUES (expr, ...), ...`
2. **`SelectStatement` AST への直接マッピング**:
   - `ast.py` の既存 `SelectStatement` ノードと 100% 互換の構造を生成し、`SQLExecutor` がそのまま実行。
3. **既存 `SQLParser._parse_select` / `_parse_cte` の置き換え**:
   - `SQLParser` 内で `parse_dql` を呼び出すように配線。
4. **品質ゲート**:
   - Xenon CC Rank A ($CC \le 4$) 達成
   - `mypy --strict` 適合
   - 既存全 SQL テスト（345 件）＋ 式テスト（21 件）＋ DQL PEG テスト（21 件）= 366 件 100% PASS

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/database/sql/dql_parser.py` に Packrat PEG による DQL 解析エンジンが実装されていること
- [x] `SELECT`, CTE (`WITH`), `JOIN`, `GROUP BY`, `HAVING`, `UNION/INTERSECT/EXCEPT`, `VALUES` が AST に変換できること
- [x] 既存 `SQLParser` から透過的に DQL パーサーが呼び出され、既存の SQL テスト全件が成功すること
- [x] `tests/database/test_sql_dql_peg.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
