---
ID: 267
種別: Feature
優先度: Low
ステータス: Closed (Completed)
---

# [FEAT/DATABASE] SQLite 完全互換化: スタンドアロン VALUES クエリ構文の実装 (ID: 267)

## 1. 概要 / Summary
SQLite 3.7.11+ 仕様 ([sqlite.org/lang_select.html#values](https://sqlite.org/lang_select.html#values)) に準拠したスタンドアロン `VALUES (...)` クエリ構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
`SELECT` 句を伴わずに `VALUES (1, 'Alice'), (2, 'Bob')` を直接トップレベル DQL として実行可能にし、デフォルト列名（`column1`, `column2`, ...）での結果返却、`ORDER BY`、`LIMIT / OFFSET`、CTE (`WITH`)、および集合演算 (`UNION` / `EXCEPT` / `INTERSECT`) との統合を実現する。

構文例:
```sql
VALUES (1, 'Alice'), (2, 'Bob');

VALUES (3, 'Charlie'), (1, 'Alice'), (2, 'Bob')
ORDER BY column1 ASC LIMIT 2;

WITH static_data AS (
    VALUES ('US', 'United States'), ('JP', 'Japan')
)
SELECT * FROM static_data;
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **入力サニタイズ / リテラル評価**:
  - `VALUES` 句内の各式・リテラルパースにおいて Python の `eval()` / `exec()` を一切使用せず、既存の安全な `_extract_field_value` および `_parse_val_type` を用いて評価する。
- **ReDoS 防御**:
  - カンマ区切りのタプルリスト `(v1, v2), (v3, v4)` のパースにおいて、ネストされた括弧を線形走査（`_extract_parenthesized_tuples`）で安全に分解する。
- **循環的複雑度統制**:
  - Xenon Rank A ($\le 5$) を厳格順守するため、タプル抽出、デフォルト列名付与、行辞書生成を各小関数に分離する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `SelectStatement` に `values_rows: Optional[List[List[Any]]] = None` を追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - トップレベルおよびサブクエリ/CTE 内での `^VALUES\s*\(...` パース処理を追加
  - タプル分解ヘルパー `_parse_values_clause_tuples` の実装
  - `ORDER BY` および `LIMIT / OFFSET` の切り出し適用
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_exec_select`: `stmt.values_rows is not None` の場合、行セット生成ロジック `_generate_values_rows` を実行
  - 列名（`column1`, `column2`, ...）の自動付与と `ORDER BY` / `LIMIT` / 集合演算の透過連携
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - 単体テスト・ORDER BY・LIMIT・CTE・集合演算連携テストを追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/267-implement-sqlite-parity-standalone-values`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `SelectStatement` に `values_rows: Optional[List[List[Any]]] = None` を追加（SQLite 仕様上の select-core と一致）。
2. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - `_parse_single_select` において、`sql` が `VALUES` で始まる場合を検出。
   - `LIMIT/OFFSET`, `ORDER BY` を抽出し、残りの `VALUES (...)` 文字列から各タプルのリテラル・式リストを抽出。
   - `SelectStatement(values_rows=rows, columns=[...], ...)` を構築。
3. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `_exec_select` で `stmt.values_rows is not None` の場合、テーブル走査を行わず `_build_rows_from_values(stmt.values_rows)` で `[{'column1': r[0], 'column2': r[1], ...}]` を構築。
   - 既存のソート（`_sort_records`）、スライス（`limit`, `offset`）、集合演算（`union`, `intersect`, etc.）にそのまま流す。
4. **テスト & 品質検証**:
   - `test_standalone_values_clause` を追加し、`pytest`, `make format`, `make static_analysis` を PASS させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `VALUES (1, 'Alice'), (2, 'Bob')` が単独で実行され、2 行の結果セット（`column1`, `column2`）が返ること。
- [x] `VALUES (...) ORDER BY column1 DESC LIMIT 1` が正しくソート・制限されて返ること。
- [x] CTE `WITH t AS (VALUES (10, 'A'), (20, 'B')) SELECT * FROM t WHERE column1 > 15` が動作すること。
- [x] 集合演算 `SELECT 1 AS column1 UNION ALL VALUES (2)` が動作すること。
- [x] `tests/database/sql/test_sql_engine.py` に検証テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
