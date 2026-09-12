---
ID: 270
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: COLLATE 照合順序句 (NOCASE, RTRIM, BINARY) の実装 (ID: 270)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/datatype3.html#collation](https://sqlite.org/datatype3.html#collation)) に準拠した `COLLATE` 句を Pure Python SQL Engine (`src/database/sql/`) に実装する。
カラム定義およびクエリ式内で `COLLATE NOCASE`（大文字小文字無視）、`COLLATE RTRIM`（末尾空白無視）、`COLLATE BINARY`（バイト比較）を指定可能にし、大文字小文字を区別しない検索やソート順序制御を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Collating Sequences](https://sqlite.org/datatype3.html#collation)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `ColumnDef` および条件句/Order句に `collate: Optional[str]` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `COLLATE (NOCASE|RTRIM|BINARY)` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): 比較処理および `ORDER BY` ソート処理における照合ロジックの適用
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/270-implement-sqlite-parity-collate-clause`

1. カラム定義時および WHERE/ORDER BY 式で `COLLATE <name>` を認識。
2. 照合器の実装:
   - `BINARY`: 標準の文字列バイト順（`a == b`, `a < b`）
   - `NOCASE`: 7-bit ASCII 大小無視（`a.lower() == b.lower()`）
   - `RTRIM`: 末尾の空白文字除去後に比較（`a.rstrip(' ') == b.rstrip(' ')`）
3. 比較述語（`=`, `!=`, `<`, `>`, `BETWEEN`, `IN`）およびソートキー関数に照合ロジックを適用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SELECT * FROM tbl WHERE name = 'alice' COLLATE NOCASE` で大文字小文字を問わず一致すること。
- [ ] `ORDER BY name COLLATE NOCASE ASC` で意図通りソートされること。
- [ ] `COLLATE RTRIM` による末尾空白無視比較が正常に動作すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
