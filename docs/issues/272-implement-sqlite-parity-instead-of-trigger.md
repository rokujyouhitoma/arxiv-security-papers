---
ID: 272
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: VIEW 向け INSTEAD OF トリガーの実装 (ID: 272)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/lang_createtrigger.html](https://sqlite.org/lang_createtrigger.html)) に準拠した `INSTEAD OF` トリガーを Pure Python SQL Engine (`src/database/sql/`) に実装する。
通常は直接更新できない `VIEW` に対して `INSERT`, `UPDATE`, `DELETE` が実行された際、ビュー自体への直接変更の代わりにトリガー本体の DML を実行して基底テーブルへ変更を透過的に転送できるようにする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite CREATE TRIGGER (INSTEAD OF)](https://sqlite.org/lang_createtrigger.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `CreateTriggerStatement` の timing 属性に `INSTEAD OF` をサポート
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `CREATE TRIGGER ... INSTEAD OF (INSERT|UPDATE|DELETE) ON view_name` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): VIEW に対する DML 実行時に `INSTEAD OF` トリガーを検出し通常更新をバイパスしてトリガー実行
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/272-implement-sqlite-parity-instead-of-trigger`

1. パーサーで `INSTEAD OF` タイミングを認識し、対象がテーブルではなく VIEW であることを検証。
2. エグゼキューターの `_exec_insert`, `_exec_update`, `_exec_delete` で、対象が VIEW でありかつ `INSTEAD OF` トリガーが登録されている場合、ビューエラーを出さずにトリガーを起動。
3. `NEW.` および `OLD.` プレースホルダーを基底テーブルへの DML にバインドして実行。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] VIEW に対して `INSTEAD OF INSERT` トリガーが作成できること。
- [ ] `INSERT INTO view_name ...` を実行した際、基底テーブルへ正しく行が挿入されること。
- [ ] `INSTEAD OF UPDATE / DELETE` も同様に動作すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
