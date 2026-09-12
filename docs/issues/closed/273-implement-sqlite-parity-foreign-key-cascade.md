---
ID: 273
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/DATABASE] SQLite 完全互換化: 外部キーカスケード (ON DELETE CASCADE / ON UPDATE SET NULL) の実装 (ID: 273)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/foreignkeys.html](https://sqlite.org/foreignkeys.html)) に準拠した外部キーアクション（`ON DELETE CASCADE`, `ON DELETE SET NULL`, `ON DELETE RESTRICT`, `ON UPDATE CASCADE`, `ON UPDATE SET NULL`, `ON UPDATE RESTRICT`）を Pure Python SQL Engine (`src/database/sql/`) に実装する。
親テーブルの行が削除または更新された際に、外部キー参照を持つ子テーブルの行を自動的に連動削除・更新できるようにし、リレーショナル整合性の自動維持（Referential Integrity Enforcement）を確立する。
また、カラムレベル定義（`REFERENCES tbl(col) ON DELETE ...`）およびテーブルレベル制約定義（`FOREIGN KEY (col) REFERENCES tbl(col) ON DELETE ...`）の両構文をサポートする。

構文例:
```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name TEXT
);

CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE ON UPDATE SET NULL
);

-- またはカラム定義形式
CREATE TABLE profiles (
    id INT PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    bio TEXT
);
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **無限再帰・循環参照防御 (DoS 防御)**:
  - 親テーブルと子テーブルの間で循環参照や多段カスケードが存在する場合にスタックオーバーフローやデッドロックが生じないよう、カスケード実行スタック（`visited_deletions: set`）で訪問済みレコードを追跡し、無限再帰を遮断。
- **データ不整合・孤立レコード防止 (Tampering 防御)**:
  - 親テーブル削除時の `CASCADE` で子レコードが確実に連動削除され、孤立参照レコード（Orphan Records）が残存しないことを保証。
  - `RESTRICT` 指定時は子レコードが存在する場合に `SQLExecutionError` を送出して親行削除をアトミックに拒否。
- **権限・トランザクション保護 (Elevation of Privilege / Transactional Integrity)**:
  - カスケード連動処理は呼び出し元の `effective_role` およびアクティブなトランザクション境界内で実行され、ロールバック時にカスケード削除・更新も確実に復元。
- **複雑度統制 (Cyclomatic Complexity)**:
  - カスケード解決ロジック、パースヘルパー、外部キー探索ハンドラーを分離し、全関数で Xenon Rank A ($\le 5$) を厳格順守。

---

## 3. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Foreign Key Support](https://sqlite.org/foreignkeys.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `ForeignKeyDef`: `child_column`, `parent_table`, `parent_column`, `on_delete`, `on_update` データクラスの定義
  - `CreateTableStatement`: `foreign_keys: List[ForeignKeyDef]` フィールドの追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_column_def`: カラム定義内の `REFERENCES ... [ON DELETE ...] [ON UPDATE ...]` 抽出
  - `_parse_create_table`: テーブル制約 `FOREIGN KEY (...) REFERENCES ...` の抽出・パース
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `TableCatalog`: `foreign_keys: List[ForeignKeyDef]` の保持
  - `_exec_delete_table`: 親レコード削除時の連動カスケード処理（CASCADE, SET NULL, RESTRICT）
  - `_exec_update_table`: 親レコード更新時の連動カスケード処理
  - `_handle_fk_delete_cascade`, `_handle_fk_update_cascade`: 専用カスケードヘルパー
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - `test_foreign_key_cascade_lifecycle`: ON DELETE CASCADE, ON DELETE SET NULL, ON UPDATE CASCADE, RESTRICT エラー等の完全検証

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/273-implement-sqlite-parity-foreign-key-cascade`

1. **AST & Parser 拡張 (`ast.py`, `parser.py`)**:
   - `ForeignKeyDef` クラスを定義。
   - `_split_column_defs` において、`FOREIGN KEY` で始まる行をテーブル制約として判定・抽出。
   - カラム定義中の `REFERENCES tbl(col) ON DELETE ... ON UPDATE ...` を抽出して `ForeignKeyDef` を生成。
2. **TableCatalog への登録 (`executor.py`)**:
   - `CreateTableStatement.foreign_keys` を `TableCatalog.foreign_keys` へ格納。
3. **カスケードエンジンの実装 (`executor.py`)**:
   - `_find_referencing_foreign_keys(parent_table: str) -> List[Tuple[TableCatalog, ForeignKeyDef]]`:
     指定された親テーブルを参照している全子テーブルと外部キー定義を取得。
   - 親行削除時 (`_cascade_delete_references`):
     - `CASCADE`: 子テーブルの `child_col == parent_val` 行を連動削除。
     - `SET NULL`: 子テーブルの `child_col` を `None` に一括更新。
     - `RESTRICT`: 子行が存在する場合に即時例外送出。
   - 親行更新時 (`_cascade_update_references`):
     - 親列の値が変更された場合、同様に `CASCADE`, `SET NULL`, `RESTRICT` を適用。
4. **テスト & 品質ゲート検証**:
   - `test_foreign_key_cascade_lifecycle` を追加し、全カスケードケースを網羅。
   - `make format`, `make static_analysis`, `pytest` を実行し、Rank A ($\le 5$)、型エラー0件を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] カラムレベルおよびテーブルレベル制約の両方で `REFERENCES parent(col) ON DELETE ... ON UPDATE ...` がパースできること。
- [x] 親テーブルの行を削除した際、`ON DELETE CASCADE` が設定された子テーブルの該当行が自動連動削除されること。
- [x] 親テーブルの行を削除した際、`ON DELETE SET NULL` が設定された子テーブルの外部キー列が `None` に更新されること。
- [x] `ON DELETE RESTRICT` により、子行が存在する場合の親行削除が拒否（例外送出）されること。
- [x] 親テーブルのキー更新時に `ON UPDATE CASCADE` / `ON UPDATE SET NULL` が連動動作すること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・結合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
