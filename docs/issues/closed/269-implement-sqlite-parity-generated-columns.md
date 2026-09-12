---
ID: 269
種別: Feature
優先度: Low
ステータス: Closed (Completed)
---

# [FEAT/DATABASE] SQLite 完全互換化: 生成列 (GENERATED ALWAYS AS) の実装 (ID: 269)

## 1. 概要 / Summary
SQLite 3.31.0+ 仕様 ([sqlite.org/gencol.html](https://sqlite.org/gencol.html)) に準拠した生成列 (`[GENERATED ALWAYS] AS (expr) [STORED | VIRTUAL]`) を Pure Python SQL Engine (`src/database/sql/`) に実装する。
他カラムの値から決定論的に導出される計算列を定義可能にし、冗長なアプリケーション層計算の排除およびクエリ参照の高速化を実現する。

構文例:
```sql
CREATE TABLE products (
    id INT PRIMARY KEY,
    price REAL,
    qty INT,
    total REAL GENERATED ALWAYS AS (price * qty) STORED,
    discounted REAL AS (price * 0.9) VIRTUAL
);
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **改ざん防止 (Tampering 防御 / Direct Write Restriction)**:
  - 生成列は他列から自動導出される読み取り専用プロパティであるため、`INSERT INTO products (id, total) VALUES (1, 100)` や `UPDATE products SET total = 50` などの明示的書き込み試行を厳格に拒否（`SQLExecutionError: cannot write to generated column 'total'` 送出）。
- **No-eval 原則 & 安全な式評価 (RCE 防御)**:
  - `GENERATED ALWAYS AS (expr)` の評価において、Python の `eval()` や `exec()` を一切使用せず、既存の安全な `_extract_field_value` および `_evaluate_binary_arithmetic`（`+`, `-`, `*`, `/`）を用いて行コンテキストから決定論的に計算。
- **ReDoS / 循環参照防御 (DoS 防御)**:
  - カラム定義パース時に `AS (expr)` の括弧構造を安全に抽出し、自身を参照する循環依存（例: `c1 AS (c1 + 1)`）を検出して `SQLParseError` を送出。
- **循環的複雑度統制**:
  - 生成列の計算および代入ブロックを `_compute_generated_columns(table, row)` として分離し、Xenon Rank A ($\le 5$) を厳格順守。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `ColumnDef` に `generated_expr: Optional[str] = None` および `is_stored: bool = False` を追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_column_def`: `(?:GENERATED\s+ALWAYS\s+)?AS\s*\((.*?)\)(?:\s+(STORED|VIRTUAL))?` 句の抽出と `ColumnDef` への格納
  - 生成列自身の名前を式内で参照していないか循環参照チェック
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `_create_new_table_storage`: `TableCatalog` に生成列定義マップ `generated_columns: Dict[str, ColumnDef]` を保持
  - `_exec_insert` / `_apply_single_update`:
    - 明示的に生成列へ値を設定しようとした場合に `SQLExecutionError`
    - レコード挿入時および更新時、`_compute_generated_columns` を呼び出して行データに計算値を自動算入
  - `_exec_select`: 射影時に `VIRTUAL` 生成列が存在する場合のオンザフライ計算補完
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - 単体テスト（STORED / VIRTUAL 定義、自動計算、書き込み拒否、UPDATE 連動）追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/269-implement-sqlite-parity-generated-columns`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `ColumnDef` に `generated_expr: Optional[str] = None` と `is_stored: bool = False` を追加。
2. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - カラム定義文字列から `(?:GENERATED\s+ALWAYS\s+)?AS\s*\((.*?)\)(?:\s+(STORED|VIRTUAL))?` を正規表現で抽出。
   - 抽出した式と `is_stored`（デフォルトは `VIRTUAL`、`STORED` 指定時は True）を `ColumnDef` に記録。
3. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `TableCatalog` に `generated_columns`（`Dict[str, ColumnDef]`）を記録。
   - `_check_generated_column_writes`: INSERT/UPDATE の代入対象に生成列が含まれているかチェックし、含まれていればエラー。
   - `_compute_generated_columns`: 行コンテキスト `row` を基に各生成列の式を計算し、`row[col_name] = computed_val` を設定。
4. **テスト & 品質検証**:
   - `tests/database/sql/test_sql_engine.py` に `test_generated_columns_lifecycle` を追加。
   - `make format`, `make static_analysis` (Rank A, mypy --strict) を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `col REAL GENERATED ALWAYS AS (price * qty) STORED` および `AS (price * 0.9) VIRTUAL` が正常に定義できること。
- [x] INSERT 時に生成列が元カラムから自動計算されて格納・SELECT 取得できること。
- [x] UPDATE で元カラムが変更された際、生成列の値が自動再計算されること。
- [x] 生成列に対して明示的に INSERT / UPDATE で値を代入しようとすると `SQLExecutionError` となること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・統合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。

