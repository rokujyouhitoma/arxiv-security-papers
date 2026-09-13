---
ID: 276
種別: Feature
優先度: Medium
ステータス: Closed
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

## 3. 脅威モデルとセキュリティ要件 / Threat Model & Security Requirements
- **No-eval セキュリティ原則**:
  - 引数に渡される JSON 文字列やパスパラメータの評価において、決して `eval()` や `exec()` を用いないこと。標準ライブラリの `json.loads` を安全に適用する。
- **DoS / ReDoS 対策**:
  - 悪意をもって深くネストされた JSON オブジェクトや循環参照に対する再帰探索の深さ上限を検証し、スタックオーバーフローを防ぐ。
- **SQL インジェクション耐性**:
  - `FROM json_each(...)` のテーブル式パースにおいて、関数引数内の文字列リテラルやカンマ、括弧を安全に字句解析・分離すること。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/json_tree.py](../../src/database/sql/json_tree.py): 新規作成。`json_each` および `json_tree` の走査・行ジェネレータロジック（Pure Python、固定8列タプル構造）
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `TableRef` に `function_name: Optional[str]` および `function_args: List[str]` フィールドを追加
- [x] [src/database/sql/parser.py](../../src/database/sql/parser.py): `_parse_single_table_ref` およびカンマ区切り/JOIN句において `json_each(...)` / `json_tree(...)` 構文の認識
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py): `_get_initial_select_rows` および `_join_table_rows` におけるテーブル値関数の評価・行展開（相関サブクエリ・相関結合カラム引数のサポート）
- [x] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加（スタンドアロン展開、エイリアス、パス指定、相関クロス結合、json_treeネスト展開）

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/276-implement-sqlite-parity-json-each-and-tree`

1. **JSON 展開コアモジュール (`src/database/sql/json_tree.py`) の実装**:
   - `json_each(json_str, path=None)`: ルート要素（または path で指定された要素）直下の要素をイテレート。
   - `json_tree(json_str, path=None)`: 深さ優先探索（DFS）で再帰的に全要素をイテレート。
   - 各行は SQLite 準拠の 8 カラムを辞書で表現:
     - `key`: オブジェクトのキー (str) または配列のインデックス (int)、ルート自身なら NULL/None
     - `value`: 値（プリミティブ型、またはサブオブジェクト/配列の JSON 文字列）
     - `type`: 'null', 'integer', 'real', 'text', 'array', 'object'
     - `atom`: プリミティブならその値、複合型なら NULL/None
     - `id`: ノードの一意な整数連番
     - `parent`: 親ノードの id（ルート直下またはルートなら NULL/None）
     - `fullkey`: `$` から始まる完全パス（例: `$.tags[0]`）
     - `path`: 親要素までのパス（例: `$.tags`）

2. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `TableRef` に `function_name: Optional[str] = None` と `function_args: List[str] = field(default_factory=list)` を追加。

3. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - `_parse_single_table_ref`: 正規表現または括弧パースにより `^(json_each|json_tree)\s*\((.*)\)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?$` を解析し、`TableRef(name=func_name, alias=..., function_name=func_name, function_args=[...])` を構築。
   - カンマ区切りの FROM 句（例: `FROM tbl, json_each(tbl.col) AS j`）の CROSS JOIN への正規化。

4. **エグゼキュータ拡張 (`src/database/sql/executor.py`)**:
   - `_get_initial_select_rows`: `table_ref.function_name in ("json_each", "json_tree")` の場合、引数をリテラル評価して行展開。
   - `_join_table_rows`: 結合先がテーブル値関数の場合、左辺行のカラム値（例: `tbl.tags_json`）を引数にバインドして動的に右辺行を生成し、クロス結合・内部結合を実行。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `SELECT key, value FROM json_each('["a", "b", "c"]')` で 3 行が取得できること。
- [x] `SELECT key, value, type, fullkey FROM json_each('{"name": "Alice", "age": 30}')` で 2 行取得できること。
- [x] パス引数 `json_each('{"a": [10, 20]}', '$.a')` で 10, 20 が取得できること。
- [x] `SELECT tbl.id, j.value FROM tbl, json_each(tbl.tags_json) j` でのクロス結合・相関行展開が動作すること。
- [x] `json_tree` によるネストされた階層オブジェクトの全件展開が正しく機能すること。
- [x] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [x] `make format`, `make static_analysis`, `xenon` Rank A (<= 5), `mypy --strict` が PASS すること。


