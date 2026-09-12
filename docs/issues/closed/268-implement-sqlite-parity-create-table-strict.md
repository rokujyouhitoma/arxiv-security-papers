---
ID: 268
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/DATABASE] SQLite 完全互換化: CREATE TABLE ... STRICT モードの実装 (ID: 268)

## 1. 概要 / Summary
SQLite 3.37.0+ 仕様 ([sqlite.org/stricttables.html](https://sqlite.org/stricttables.html)) に準拠した `CREATE TABLE ... STRICT` 構文を Pure Python SQL Engine (`src/database/sql/`) に実装する。
動的型付け（柔軟な型親和性・Type Affinity）を排し、許可されたデータ型（`INT`, `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY`）に対する厳格なスキーマ検証・型変換・不整合時のエラー送出を保証する。

構文例:
```sql
CREATE TABLE strict_users (
    id INT PRIMARY KEY,
    name TEXT NOT NULL,
    score REAL,
    avatar BLOB,
    extra ANY
) STRICT;
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / Type Safety)
- **入力サニタイズ / 型強制 (Tampering / Input Validation)**:
  - 柔軟な型親和性による予期せぬ型混在（例: 数値列にスクリプトや不正文字列が保存される問題）を防止。
  - STRICT モードでは `INT` 列に文字列 `'123'` が来ても厳格に拒否（または明示的変換不可能な場合は即座に `SQLExecutionError` 送出）。
- **ReDoS 防御 & スキーマパーサー堅牢性**:
  - `CREATE TABLE ... ) [STRICT] [, WITHOUT ROWID]` のテーブルオプション抽出において、貪欲正規表現を排し正規化トークン分割で処理。
- **No-eval 原則**:
  - 型検証において `eval` / `exec` を一切使用せず、Python 組み込みの `isinstance(val, (int, float, str, bytes))` および型変換チェックのみで判定。
- **循環的複雑度統制**:
  - 各データ型の厳格検証ロジックを `_validate_strict_column_type(col_name, declared_type, value)` として小関数に分離し、Xenon Rank A ($\le 5$) を維持。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `CreateTableStatement` に `strict: bool = False` を追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_create_table`: テーブル定義括弧末尾の `STRICT` キーワードの抽出
  - `STRICT` 指定時、定義カラムのデータ型が `{'INT', 'INTEGER', 'REAL', 'TEXT', 'BLOB', 'ANY'}` のみに限定されているかバリデーション（違反時は `SQLParseError`）
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_exec_create_table`: `table_meta`（スキーマ定義）に `strict: bool` を記録
  - `_exec_insert` / `_exec_update`: 対象テーブルが `strict` の場合、全入力値に対して `_validate_strict_row` を実行
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - 正常系（STRICT 定義、各種型の正常 INSERT/UPDATE）
  - 異常系（未許可型での CREATE TABLE、型不一致データの INSERT/UPDATE 拒絶）テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/268-implement-sqlite-parity-create-table-strict`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `CreateTableStatement` に `strict: bool = False` を追加。
2. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - `CREATE TABLE <name> (...) [table_options]` の正規表現を拡張。
   - `table_options` から `STRICT` の存在をフラグ化。
   - `strict=True` の場合、全カラム定義の `data_type.upper()` が `INT`, `INTEGER`, `REAL`, `TEXT`, `BLOB`, `ANY` のいずれかであることを検証。違反時は `SQLParseError(f"Unknown datatype for <col> in STRICT table: {dt}")`。
3. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `table_catalog` のメタデータに `is_strict` を保持。
   - 挿入および更新時に各カラムの値をチェック:
     - `INT` / `INTEGER`: `isinstance(val, int)` (bool を除く) または整数として完全表現可能な値。
     - `REAL`: `isinstance(val, (int, float))` (bool を除く)。
     - `TEXT`: `isinstance(val, str)`.
     - `BLOB`: `isinstance(val, bytes)`.
     - `ANY`: 任意。
     - `NULL`: NOT NULL 制約に反しない限り全型で許可。
     - 違反時は `SQLExecutionError(f"cannot store {type(val).__name__} in {data_type} column in STRICT table")`。
4. **テスト & 品質検証**:
   - `tests/database/sql/test_sql_engine.py` に `test_create_table_strict_mode` を追加。
   - `make format`, `make static_analysis` (Rank A, mypy --strict) を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `CREATE TABLE t (id INT, name TEXT) STRICT` が正常にパース・作成されること。
- [x] 未定義・非推奨型（例: `VARCHAR(100)`, `DATETIME`）を `STRICT` テーブルに指定すると `SQLParseError` が発生すること。
- [x] 型不一致データ（例: `INT` 列に文字列 `'abc'` や `TEXT` 列に数値 `123`）の `INSERT` / `UPDATE` で `SQLExecutionError` が発生すること。
- [x] `ANY` 列に数値、文字列、バイト列など任意の型が格納できること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・統合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。


