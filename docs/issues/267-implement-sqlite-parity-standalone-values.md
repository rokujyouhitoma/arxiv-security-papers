---
ID: 267
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: スタンドアロン VALUES クエリ構文の実装 (ID: 267)

## 1. 概要 / Summary
SQLite 3.7.11+ 仕様 ([sqlite.org/lang_select.html#values](https://sqlite.org/lang_select.html#values)) に準拠したスタンドアロン `VALUES (...)` 式クエリを Pure Python SQL Engine (`src/database/sql/`) に実装する。
`SELECT` 句を伴わずに `VALUES (1, 'Alice'), (2, 'Bob')` を直接トップレベル DQL として実行可能にし、CTE やサブクエリ内での簡易インラインテーブル生成を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite VALUES clause](https://sqlite.org/lang_select.html#values)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `ValuesStatement` AST ノードの追加または `SelectStatement` への包含
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `^VALUES\s*\(...` のトップレベル検出およびパース
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `column1`, `column2`... をキーとする行セット生成ロジック
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/267-implement-sqlite-parity-standalone-values`

1. `parser.py` で `VALUES` から始まる構文を解釈し、各行のタプルリストを抽出。
2. デフォルト列名（`column1`, `column2`, ...）を持つ結果セット辞書を生成。
3. CTE (`WITH t AS (VALUES (1), (2)) SELECT ...`) や集合演算 (`SELECT 1 UNION VALUES (2)`) とのシームレスな統合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `VALUES (1, 'Alice'), (2, 'Bob')` が単独で実行され 2 行の結果セットが返ること。
- [ ] 列名が `column1`, `column2` 等で返却されること。
- [ ] CTE や `UNION` 演算との連動が正常に動作すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
