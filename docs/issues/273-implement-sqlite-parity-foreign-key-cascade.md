---
ID: 273
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: 外部キーカスケード (ON DELETE CASCADE / ON UPDATE SET NULL) の実装 (ID: 273)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/foreignkeys.html](https://sqlite.org/foreignkeys.html)) に準拠した外部キーアクション（`ON DELETE CASCADE`, `ON DELETE SET NULL`, `ON UPDATE CASCADE`, `ON UPDATE RESTRICT`）を Pure Python SQL Engine (`src/database/sql/`) に実装する。
親テーブルの行が削除または更新された際に、外部キー参照を持つ子テーブルの行を自動的に連動削除・更新できるようにし、リレーショナル整合性の自動維持を確立する。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Foreign Key Support](https://sqlite.org/foreignkeys.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `ForeignKeyConstraint` に `on_delete: Optional[str]` および `on_update: Optional[str]` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `REFERENCES tbl(col) ON DELETE ... ON UPDATE ...` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): DELETE/UPDATE 実行時のカスケードエンジン（参照テーブル検知と連動処理）
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/273-implement-sqlite-parity-foreign-key-cascade`

1. カラムおよびテーブル制約の外部キー定義で `ON DELETE (CASCADE|SET NULL|RESTRICT|NO ACTION|SET DEFAULT)` を認識。
2. テーブルカタログに外部キーの依存グラフ（親テーブル $\rightarrow$ 子テーブル・外部キー列の参照インデックス）を保持。
3. 親テーブルの `_exec_delete` 時に、`PRAGMA foreign_keys = ON` の場合、参照している子テーブルの該当行を特定し、指定されたアクション（削除または NULL セット）を再帰実行。
4. `RESTRICT` 時に子行が存在する場合は `SQLExecutionError`（外部キー制約違反）を送出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 親テーブルの行を削除した際、`ON DELETE CASCADE` が設定された子テーブルの関連行が自動削除されること。
- [ ] `ON DELETE SET NULL` で子テーブルの外部キー列が `None` に更新されること。
- [ ] `PRAGMA foreign_keys` の有効化/無効化切り替えが機能すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
