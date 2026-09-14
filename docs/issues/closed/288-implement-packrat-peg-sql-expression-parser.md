---
ID: 288
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] SQL 複雑式（論理演算・比較・CASE・関数）向け Packrat PEG 式パーサーの実装 (DSN-25 / DSN-05 連携) (ID: 288)

## 1. 概要 / Summary
設計仕様書 [DSN-25](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.2節) および [DSN-05](../designs/DSN-05-database_engine_architecture.md) に基づき、現在 `src/database/sql/parser.py` で手書き正規表現と文字列置換（`__BETWEEN_AND__` など）で行われている脆弱な式解析を刷新し、Packrat PEG エンジン (`src/core/structures/peg.py`) を用いた **SQL 式（Expression）パーサー (`src/database/sql/expr_parser.py`)** を新規実装した。
外部依存を一切使用せず、ゼロ外部依存の純粋 Python で以下の SQL 式文法を線形時間 $O(N)$ で厳密に構文木（AST）化し、既存の SQL 構文解析パイプラインおよび実行エンジンへの連携基盤を確立した。

- リテラル: 整数、浮動小数点数、文字列（シングル/ダブルクォート、エスケープ対応）、真偽値 (`TRUE`, `FALSE`)、`NULL`
- 識別子 / 列参照: 単純列名、テーブル修飾列名 (`table.col`)、JSON 抽出演算子 (`data->>'key'`)
- 算術演算子: 加算 `+`、減算 `-`、乗算 `*`、除算 `/`、剰余 `%`（標準の演算子優先順位）
- 比較演算子: `=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`
- 特殊述語:
  - `IS NULL` / `IS NOT NULL`
  - `BETWEEN expr AND expr` / `NOT BETWEEN expr AND expr`
  - `LIKE pattern [ESCAPE char]` / `NOT LIKE`
  - `GLOB pattern`
  - `IN (val1, val2, ...)` / `IN (SELECT ...)`
  - `EXISTS (SELECT ...)` / `NOT EXISTS (SELECT ...)`
  - `MATCH pattern`
- 論理演算子と括弧ネスト: `AND`, `OR`, `NOT`、および任意深度の括弧式 `(expr)`
- 関数呼び出し: `FUNC(arg1, arg2, ...)`、`COUNT(*)`
- CASE 条件分岐式: `CASE [expr] WHEN cond THEN result ... [ELSE default] END`

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-25-pure_python_packrat_peg_parser_engine.md](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) (第5.2節)
- 設計書: [DSN-05-database_engine_architecture.md](../designs/DSN-05-database_engine_architecture.md)
- 前提成果物: [src/core/structures/peg.py](../../src/core/structures/peg.py) (Issue 284)
- 連携先モジュール: [src/database/sql/parser.py](../../src/database/sql/parser.py), [src/database/sql/ast.py](../../src/database/sql/ast.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/expr_parser.py](../../src/database/sql/expr_parser.py) (新規: Packrat PEG SQL 式パーサーエンジン)
- [x] [src/database/sql/__init__.py](../../src/database/sql/__init__.py) (公開エクスポートの追加)
- [x] [tests/database/test_sql_expr_peg.py](../../tests/database/test_sql_expr_peg.py) (新規: SQL 式構文網羅テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/288-packrat-peg-sql-expression-parser`

1. **式 AST クラス群の定義 (`src/database/sql/expr_parser.py`)**:
   - `LiteralExpr`: `value: Any`, `to_sql()`
   - `ColumnRefExpr`: `column: str`, `table: Optional[str] = None`, `json_path: Optional[str] = None`, `to_sql()`
   - `UnaryOpExpr`: `op: str`, `operand: SQLExpr`, `to_sql()`
   - `BinaryOpExpr`: `op: str`, `left: SQLExpr`, `right: SQLExpr`, `to_sql()`
   - `BetweenExpr`: `expr: SQLExpr`, `low: SQLExpr`, `high: SQLExpr`, `is_not: bool = False`, `to_sql()`
   - `InExpr`: `expr: SQLExpr`, `values: List[SQLExpr]`, `subquery: Optional[str] = None`, `is_not: bool = False`, `to_sql()`
   - `IsNullExpr`: `expr: SQLExpr`, `is_not: bool = False`, `to_sql()`
   - `LikeExpr`: `expr: SQLExpr`, `pattern: SQLExpr`, `operator: str`, `escape: Optional[str] = None`, `is_not: bool = False`, `to_sql()`
   - `FunctionCallExpr`: `name: str`, `args: List[SQLExpr]`, `is_star: bool = False`, `is_distinct: bool = False`, `to_sql()`
   - `CaseExpr`: `base_expr: Optional[SQLExpr]`, `when_then_list: List[Tuple[SQLExpr, SQLExpr]]`, `else_expr: Optional[SQLExpr] = None`, `to_sql()`
2. **PEG 文法階層の定義 (相互再帰・優先順位対応)**:
   - `PrimaryExpr`: Literal / FunctionCall / ColumnRef / `( Expr )` / CaseExpr
   - `UnaryExpr`: `+`, `-`, `NOT` PrimaryExpr
   - `MultExpr`: Unary (`*` / `/` / `%` Unary)*
   - `AddExpr`: Mult (`+` / `-` Mult)*
   - `PredicateExpr`: Add (`BETWEEN` / `IN` / `IS NULL` / `LIKE` / `GLOB` / `MATCH` / Comparison Add)
   - `AndExpr`: Predicate (`AND` Predicate)*
   - `OrExpr`: And (`OR` And)*
3. **互換レイヤーとユーティリティ**:
   - `parse_sql_expr(text: str) -> SQLExpr`: 高レベル解析関数
   - `SQLExpr.to_legacy_dict() -> Optional[Dict[str, Any]]`: 既存 RDBMS 実行エンジンが解釈可能なフラット辞書への変換ブリッジ
4. **品質ゲート遵守**:
   - 全関数 Xenon CC Rank A (<= 4)、`mypy --strict` エラー 0 件。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `src/database/sql/expr_parser.py` に Packrat PEG ベースの SQL 式パーサーが実装されていること
- [x] 算術演算子および比較演算子が優先順位に従って正確に階層 AST 化されること
- [x] `AND`, `OR` および括弧ネスト式（例: `(a = 1 OR b = 2) AND c = 3`）が正しくパースされること
- [x] `BETWEEN ... AND ...`、`IN (...)`、`IS NULL` などの特殊述語がパースできること
- [x] `CASE WHEN ... THEN ... ELSE ... END` 式および関数呼び出しがパースできること
- [x] `tests/database/test_sql_expr_peg.py` が 100% PASS すること (21/21 PASS)
- [x] `make check_format` および `make static_analysis` (xenon A, mypy strict) が 100% PASS すること
