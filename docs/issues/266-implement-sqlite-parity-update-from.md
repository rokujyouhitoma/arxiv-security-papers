---
ID: 266
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: UPDATE ... FROM (Join Update) 構文の実装 (ID: 266)

## 1. 概要 / Summary
SQLite 3.33.0+ 仕様 ([sqlite.org/lang_update.html](https://sqlite.org/lang_update.html)) に準拠した `UPDATE ... FROM` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
他テーブルと結合しながら対象テーブルの行を一括更新できるようにし、複雑な DML 変換や相関サブクエリなしでの結合更新を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite UPDATE](https://sqlite.org/lang_update.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `UpdateStatement` に `from_table: Optional[TableRef]` および `joins: List[JoinClause]` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `UPDATE tbl SET ... FROM ... [JOIN ...] WHERE ...` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): 結合行とのマッチングおよび値解決・更新ロジックの実装
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/266-implement-sqlite-parity-update-from`

1. AST に `from_table` および `joins` を持たせる。
2. パーサーで `SET assignments` と `WHERE` の間に挟まる `FROM ...` 句を抽出しテーブル結合構文として解析。
3. エグゼキューターで `FROM` 句のテーブル群をスキャン・結合し、ON/WHERE 条件に合致した行に基づいて対象テーブルのカラムを更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `UPDATE t1 SET c1 = t2.v FROM t2 WHERE t1.id = t2.id` が正しく実行されること。
- [ ] `JOIN` を含む `UPDATE t1 SET ... FROM t2 JOIN t3 ON ... WHERE ...` が動作すること。
- [ ] `RETURNING` 句およびトリガー発火との連携が正常に動作すること。
- [ ] `tests/database/sql/test_sql_engine.py` に検証テストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
