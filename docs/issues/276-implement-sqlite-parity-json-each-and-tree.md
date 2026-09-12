---
ID: 276
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: テーブル値関数 json_each() / json_tree() の実装 (ID: 276)

## 1. 概要 / Summary
SQLite 3.38.0+ 仕様 ([sqlite.org/json1.html#jeach](https://sqlite.org/json1.html#jeach)) に準拠したテーブル値関数（Table-Valued Functions）`json_each(json [, path])` および `json_tree(json [, path])` を Pure Python SQL Engine (`src/database/sql/`) に実装する。
JSON 配列や階層構造化オブジェクトを行セットとして展開し、`FROM json_each(...)` や `JOIN json_each(...)` を用いて半構造化データを SQL リレーショナル代数で柔軟に集計・走査可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite JSON Table-Valued Functions](https://sqlite.org/json1.html#jeach)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `TableRef` に関数テーブル（Table-Valued Function）の表現を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `FROM json_each(...)` および `JOIN json_each(...)` のパース
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): JSON 走査エンジンによる動的タプル行（key, value, type, atom, id, parent, fullkey, path）生成
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/276-implement-sqlite-parity-json-each-and-tree`

1. `FROM` / `JOIN` 句の解析で、テーブル名の代わりに `json_each(json_expr)` や `json_tree(json_expr)` を認識。
2. 対象 JSON 文字列（または結合元テーブルのカラム値）をパースし、SQLite 公式仕様に規定された固定スキーマの仮想行リストを生成:
   - `key`: オブジェクトのキーまたは配列のインデックス
   - `value`: 値（プリミティブまたは JSON サブツリー）
   - `type`: 'null', 'integer', 'real', 'text', 'array', 'object'
   - `fullkey`: ルートからの JSONPath
   - `path`: 親要素までのパス
3. `json_tree` では深さ優先探索（DFS）で再帰的にすべてのネスト要素を行として展開。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SELECT key, value FROM json_each('["a", "b", "c"]')` で 3 行が取得できること。
- [ ] `SELECT tbl.id, j.value FROM tbl, json_each(tbl.tags_json) j` でのクロス結合行展開が動作すること。
- [ ] `json_tree` によるネストされた階層オブジェクトの全件展開が正しく機能すること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
