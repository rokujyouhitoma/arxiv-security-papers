---
ID: 258
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT] SQLite 完全互換化 Phase 3: DDL ライフサイクル & VIEW (ALTER TABLE, DROP INDEX, REINDEX, CREATE/DROP VIEW) の実装 (ID: 258)

## 1. 概要 / Summary
[DSN-05-01] SQLite 完全互換化ロードマップの Phase 3 として、Pure Python SQL Engine (`src/database/sql/`) におけるスキーマ変更、インデックスライフサイクル管理、および仮想ビュー（VIEW）機能を実装する。
具体的には、運用中テーブルの改名・列追加・列削除・列改名を行う `ALTER TABLE`、不要インデックスを安全に削除する `DROP INDEX`、全件走査でインデックスを最適化・再構築する `REINDEX`、およびクエリをカプセル化して再利用可能にする `CREATE VIEW` / `DROP VIEW` をサポートする。

---

## 2. トレーサビリティ / Traceability
- 関連仕様書: [[DSN-05-01] 6.3 Phase 3: DDL ライフサイクル & VIEW](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md#63-phase-3-ddl-ライフサイクル完全化--viewスキーマ変更仮想ビュー)
- 準拠仕様: [SQLite Syntax Diagrams: alter-table-stmt, drop-index-stmt, reindex-stmt, create-view-stmt](https://sqlite.org/syntax/alter-table-stmt.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ast.py](../src/database/sql/ast.py): `AlterTableStatement`, `DropIndexStatement`, `ReindexStatement`, `CreateViewStatement`, `DropViewStatement` 追加
- [x] [src/database/sql/parser.py](../src/database/sql/parser.py): 各 DDL 構文パーサーの新設
- [x] [src/database/sql/executor.py](../src/database/sql/executor.py): スキーマメタデータ変更、物理ファイルリネーム、インデックス破棄・再構築、ビューインライン展開
- [x] [tests/database/sql/test_sql_engine.py](../tests/database/sql/test_sql_engine.py): ALTER TABLE, DROP INDEX, VIEW 単体テスト追加
- [x] [docs/issues/README.md](README.md): Issue 台帳の登録・追跡

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/258-implement-sqlite-parity-phase3-ddl-lifecycle-and-view`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `SQLCommandType.ALTER_TABLE`, `DROP_INDEX`, `REINDEX`, `CREATE_VIEW`, `DROP_VIEW` を追加。
   - それぞれの AST データクラスを定義。
2. **Parser 拡張 (`src/database/sql/parser.py`)**:
   - `ALTER TABLE <tbl> RENAME TO <new_tbl>`
   - `ALTER TABLE <tbl> RENAME COLUMN <old_col> TO <new_col>`
   - `ALTER TABLE <tbl> ADD COLUMN <col_def>`
   - `ALTER TABLE <tbl> DROP COLUMN <col>`
   - `DROP INDEX [IF EXISTS] <idx_name>`
   - `REINDEX [<tbl_or_idx>]`
   - `CREATE VIEW [IF NOT EXISTS] <view_name> AS <select_stmt>` / `DROP VIEW [IF EXISTS] <view_name>`
3. **Executor 拡張 (`src/database/sql/executor.py`)**:
   - `_exec_alter_table`: スキーマ定義辞書の更新、既存レコード辞書のキー更新、ファイルリネーム。
   - `_exec_drop_index`: `table.btree_indexes` または HNSW インデックスの破棄。
   - `_exec_view`: ビューを `views` カタログに保存し、SELECT クエリ実行時に CTE と同様にサブクエリ展開して透過実行。
4. **セキュリティ & 品質規律**:
   - No-eval 原則遵守。Xenon CC Rank A ($\le 5$)、Mypy --strict 0 errors。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ALTER TABLE tbl RENAME TO new_tbl` でテーブル名およびファイルが正しく変更されること。
- [x] `ALTER TABLE tbl ADD COLUMN col VARCHAR DEFAULT 'def'` で全行に新列とデフォルト値が追加されること。
- [x] `DROP INDEX idx_name` で指定インデックスが安全に破棄され、以降の EXPLAIN で利用されなくなること。
- [x] `CREATE VIEW v_active AS SELECT * FROM tbl WHERE is_active = 1` 定義後、`SELECT * FROM v_active` で正常に結果が返却されること。
- [x] `tests/database/sql/test_sql_engine.py` に単体テストを追加し、既存テストを含む全テストが PASS すること。
- [x] `make format`, `make static_analysis` (xenon CC Rank A <= 5, mypy --strict) が 100% PASS すること。
