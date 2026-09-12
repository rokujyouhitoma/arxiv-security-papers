---
ID: 274
種別: Feature
優先度: Low
ステータス: Closed (完了)
クローズ日: 2026-09-13
---

# [FEAT/DATABASE] SQLite 完全互換化: 拡張 PRAGMA (table_xinfo, user_version, foreign_key_list) の実装 (ID: 274)

## 1. 概要 / Summary
SQLite 公式仕様 ([sqlite.org/pragma.html](https://sqlite.org/pragma.html)) に準拠した拡張 PRAGMA コマンド（`PRAGMA table_xinfo(tbl)`, `PRAGMA user_version`, `PRAGMA user_version = N`, `PRAGMA foreign_key_list(tbl)`）を Pure Python SQL Engine (`src/database/sql/`) に実装する。
生成列や非表示列のメタデータ照会、外部キーリレーションのリスト化、およびスキーママイグレーションツールのバージョン管理（Flyway / Alembic / Prisma 等の SQLite アダプター連携）をネイティブサポートする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様:
  - [SQLite PRAGMA Statements: table_xinfo](https://sqlite.org/pragma.html#pragma_table_xinfo)
  - [SQLite PRAGMA Statements: user_version](https://sqlite.org/pragma.html#pragma_user_version)
  - [SQLite PRAGMA Statements: foreign_key_list](https://sqlite.org/pragma.html#pragma_foreign_key_list)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-05 データベースエンジンアーキテクチャ設計書](../designs/DSN-05-database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/ast.py](../../src/database/sql/ast.py): `PragmaStatement`（既存定義の確認・必要に応じた拡張）
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_pragma_stmt` の正規表現強化（クォート付き引数 `'tbl'`、代入構文 `name = val`、空白寛容化）
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `SQLExecutor.__init__`: `self.user_version: int = 0` の初期化
  - `_col_defs_to_pragma_rows` / `_infer_meta_pragma_rows`: `is_xinfo: bool = False` 引数の追加と `hidden` 列の計算（0: 通常列, 2: VIRTUAL 生成列, 3: STORED 生成列）
  - `_exec_pragma_table_xinfo`: `PRAGMA table_xinfo(table_name)` の実行処理
  - `_exec_pragma_user_version`: `PRAGMA user_version` のゲッター/セッター（代入時は整数設定、参照時は `[{"user_version": N}]` 返却）
  - `_exec_pragma_foreign_key_list`: `PRAGMA foreign_key_list(table_name)` の実行処理（`id`, `seq`, `table`, `from`, `to`, `on_update`, `on_delete`, `match`）
  - `_exec_pragma`: `table_xinfo`, `user_version`, `foreign_key_list` のディスパッチ登録
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト群の追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/274-implement-sqlite-parity-extended-pragma`

### 4.1 Parser の改修 (`src/database/sql/parser.py`)
- `_parse_pragma_stmt(sql: str) -> Optional[PragmaStatement]`:
  - 正規表現を改修し、以下の構文を柔軟に捕捉:
    - `PRAGMA table_xinfo(tbl)` / `PRAGMA table_xinfo('tbl')`
    - `PRAGMA user_version`
    - `PRAGMA user_version = 42` / `PRAGMA user_version(42)`
    - `PRAGMA foreign_key_list(tbl)` / `PRAGMA foreign_key_list('tbl')`
  - 引数や代入値のシングル/ダブルクォートを自動除去して正規化。

### 4.2 Executor の拡張 (`src/database/sql/executor.py`)
1. **`user_version` 管理**:
   - `self.user_version: int = 0`
   - 代入時: `val` を `int` にパースして格納。返り値は空行セット。
   - 参照時: `[{"user_version": self.user_version}]` を返却。
2. **`table_xinfo` 実装**:
   - `_exec_pragma_table_info` に `is_xinfo: bool = False` フラグを追加。
   - 生成列（`ColumnDef.generated_expr` が存在）の場合:
     - `is_stored == True` なら `hidden = 3`
     - `is_stored == False` なら `hidden = 2`
   - 通常列なら `hidden = 0`
   - 通常の `table_info` では VIRTUAL 生成列（`hidden = 2`）を除外（SQLite 3.31+ 準拠）。
3. **`foreign_key_list` 実装**:
   - `_exec_pragma_foreign_key_list(table_name)`:
   - `tcat.foreign_keys`（`List[ForeignKeyDef]`）から各外部キー定義を抽出:
     - `id`: インデックス番号 (0, 1, ...)
     - `seq`: 0
     - `table`: `fk.parent_table`
     - `from`: `fk.child_column`
     - `to`: `fk.parent_column`
     - `on_update`: `fk.on_update`
     - `on_delete`: `fk.on_delete`
     - `match`: `"NONE"`

### 4.3 セキュリティ・品質ゲート
- **No-eval 原則**: 文字列評価や数値変換において `eval()` を一切使用せず `int(val)` を用いる。
- **循環的複雑度 (Cyclomatic Complexity)**: 各メソッドで Xenon Rank A ($\le 5$) を維持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `PRAGMA user_version` が初期値 0 を返却すること。
- [ ] `PRAGMA user_version = 10` でバージョン更新され、その後の参照で 10 が取得できること。
- [ ] 通常列・VIRTUAL生成列・STORED生成列を含むテーブルにおいて、`PRAGMA table_xinfo` が `hidden` 属性（0, 2, 3）を正確に出力すること。
- [ ] 通常の `PRAGMA table_info` では VIRTUAL 生成列が非表示となること。
- [ ] `PRAGMA foreign_key_list(tbl)` が親テーブル、親カラム、子カラム、カスケードアクション（`on_delete`, `on_update`）を正確に出力すること。
- [ ] 存在しないテーブルに対する `table_xinfo`, `foreign_key_list` が空行セット（エラーではなく正常な 0 件）を返すこと。
- [ ] `tests/database/sql/test_sql_engine.py` に上記すべての検証テストを追加し 100% PASS すること。
- [ ] `make format` (flake8, isort, black), `make static_analysis` (xenon, mypy) が 100% PASS すること。
