---
ID: 268
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: CREATE TABLE ... STRICT モードの実装 (ID: 268)

## 1. 概要 / Summary
SQLite 3.37.0+ 仕様 ([sqlite.org/stricttables.html](https://sqlite.org/stricttables.html)) に準拠した `CREATE TABLE ... STRICT` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
動的型付け（柔軟な型親和性）を排し、許可されたデータ型（`INT`, `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY`）に対する厳格な型検証・型変換エラー送出を保証する。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Strict Tables](https://sqlite.org/stricttables.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `CreateTableStatement` に `strict: bool = False` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `CREATE TABLE ... ) STRICT` 構文のパースおよび未許可データ型の検証
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): `TableCatalog` への `strict` 属性保持および INSERT/UPDATE 時の厳格型検査
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 正常系・異常系テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/268-implement-sqlite-parity-create-table-strict`

1. `CreateTableStatement` に `strict` フラグを追加。
2. テーブル末尾の `STRICT` キーワード（例: `) STRICT, WITHOUT ROWID`）を認識。
3. `STRICT` テーブル定義時にカラム型が `INT`, `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY` のいずれかであることを検証（違反時は `SQLParseError`）。
4. データ挿入・更新時、カラム型に合致しない値（例: `INT` 列に文字列 'abc'）が渡された場合に `SQLExecutionError` を送出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `CREATE TABLE t (id INT, name TEXT) STRICT` が正常にパース・作成されること。
- [ ] 未定義の型（例: `VARCHAR(100)`）を `STRICT` テーブルに指定するとエラーになること。
- [ ] 型不一致データの `INSERT` / `UPDATE` で `SQLExecutionError` が発生すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
