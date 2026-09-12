---
ID: 270
種別: Feature
優先度: Low
ステータス: Closed (Completed)
---

# [FEAT/DATABASE] SQLite 完全互換化: COLLATE 照合順序句 (NOCASE, RTRIM, BINARY) の実装 (ID: 270)

## 1. 概要 / Summary
SQLite 3 系列公式仕様 ([sqlite.org/datatype3.html#collation](https://sqlite.org/datatype3.html#collation)) に準拠した `COLLATE` 照合順序句（`NOCASE`, `RTRIM`, `BINARY`）を Pure Python SQL Engine (`src/database/sql/`) に実装する。
テーブル定義時のカラム指定 (`col TEXT COLLATE NOCASE`)、WHERE 比較式 (`WHERE name = 'alice' COLLATE NOCASE`)、および ORDER BY ソート句 (`ORDER BY name COLLATE NOCASE ASC`) において柔軟かつ決定論的なテキスト照合を実現し、大文字・小文字を無視した検索・ソートや末尾空白の正規化比較を可能にする。

構文例:
```sql
-- 1. カラム定義レベルの照合順序指定
CREATE TABLE users (
    id INT PRIMARY KEY,
    username TEXT COLLATE NOCASE,
    tag TEXT COLLATE RTRIM
);

-- 2. クエリ条件レベルでの明示的照合順序
SELECT * FROM users WHERE username = 'admin' COLLATE NOCASE;

-- 3. ORDER BY ソート句での明示的照合順序
SELECT * FROM users ORDER BY username COLLATE NOCASE ASC;
```

---

## 2. セキュリティ & アーキテクチャ脅威分析 (STRIDE / No-eval 原則)
- **改ざん防止 & 入力検証 (Tampering 防御)**:
  - 照合順序名は許可されたホワイトリスト（`NOCASE`, `RTRIM`, `BINARY`）のみを検証・受容。未定義の照合順序が指定された場合は `SQLParseError`（または `SQLExecutionError`）を即時送出し、不正な識別子注入を防止。
- **No-eval 原則 & 決定論的比較 (RCE / Injection 防御)**:
  - 照合処理はすべて Pure Python の文字列変換メソッド（`str.lower()`, `str.rstrip(' ')`）を用いた決定論的比較関数により実現し、動的コード評価（`eval`, `exec`）を一切排除。
- **DoS / ReDoS 防御**:
  - 正規表現を用いた照合名パースは `\bCOLLATE\s+([a-zA-Z0-9_]+)\b` の単純マッチとし、破滅的バックトラッキングを排除。
- **循環的複雑度 (Cyclomatic Complexity) 統制**:
  - 照合トランスフォーム処理 `_collate_transform(val, collation)`、カラム照合解決 `_resolve_column_collation(col, explicit, table)`、およびソートキー関数 `_sort_key` を責務分離し、全関数で Xenon Rank A ($\le 5$) を厳格順守。

---

## 3. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Collating Sequences](https://sqlite.org/datatype3.html#collation)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [src/database/sql/ast.py](../../src/database/sql/ast.py):
  - `ColumnDef`: `collate: Optional[str] = None` を追加
  - `SelectStatement`: `order_collate: Optional[str] = None` を追加
- [src/database/sql/parser.py](../../src/database/sql/parser.py):
  - `_parse_column_def`: `COLLATE\s+(NOCASE|RTRIM|BINARY)` のパースと `ColumnDef.collate` への設定
  - `_extract_order_by_clause`: `ORDER BY col [COLLATE collation] [ASC|DESC]` のパース
  - `_parse_cmp_clause` 等の WHERE パーサー: `(?:COLLATE\s+([a-zA-Z0-9_]+))?` のパースと条件辞書への `collate` 格納
- [src/database/sql/executor.py](../../src/database/sql/executor.py):
  - `TableCatalog`: `column_collations: Dict[str, str]` の保持
  - `_collate_transform`: 照合順序に応じた正規化値（`NOCASE`: `lower()`, `RTRIM`: `rstrip(' ')`, `BINARY`: そのまま）の生成
  - `_eval_comparison` / `_eval_relational` / `_eval_membership`: 条件またはカラム定義由来の照合順序を適用して比較
  - `_sort_key` / `_sort_and_paginate`: 指定の照合順序を用いたソートキー算出
- [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py):
  - 単体テスト（NOCASE 比較, RTRIM 比較, BINARY 比較, ORDER BY NOCASE, カラムデフォルト照合順序）追加

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/270-implement-sqlite-parity-collate-clause`

1. **AST 拡張 (`src/database/sql/ast.py`)**:
   - `ColumnDef` に `collate: Optional[str] = None` を追加。
   - `SelectStatement` に `order_collate: Optional[str] = None` を追加。
2. **パーサー拡張 (`src/database/sql/parser.py`)**:
   - カラム定義パーサー `_parse_column_def` で `\bCOLLATE\s+([a-zA-Z0-9_]+)\b` を抽出し、大文字正規化してホワイトリスト検証（`NOCASE`, `RTRIM`, `BINARY`）。
   - `_extract_order_by_clause` で `COLLATE` 句を抽出し `(clean_sql, order_by, order_desc, order_collate)` を返却。
   - `_parse_cmp_clause` で末尾の `COLLATE <name>` を抽出し、`{"column": col, "operator": op, "value": val, "collate": name}` として返却。
3. **エグゼキューター拡張 (`src/database/sql/executor.py`)**:
   - `TableCatalog` 生成時に `column_collations = {c.name: c.collate for c.columns if c.collate}` を記録。
   - `_collate_transform(val, collation)` を導入。
   - 比較述語評価（`_eval_comparison`, `_eval_relational`, `_eval_membership`）で、条件辞書の `collate` または対象カラムの定義照合順序を取得してトランスフォーム後に比較。
   - `_sort_key(row, order_by, order_collate)` で、明示的 `order_collate` またはカラム定義の照合順序を取得してソートキーを変換。
4. **テスト & 品質検証**:
   - `tests/database/sql/test_sql_engine.py` に `test_collate_clause_lifecycle` を追加し、NOCASE/RTRIM/BINARY の WHERE 比較、ORDER BY ソート、カラム定義デフォルト照合を網羅。
   - `make format`, `make static_analysis` (Rank A, mypy --strict) の 100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `CREATE TABLE users (id INT PRIMARY KEY, name TEXT COLLATE NOCASE)` でカラム定義に照合順序が保持されること。
- [x] `SELECT * FROM users WHERE name = 'alice' COLLATE NOCASE` で大文字小文字不問でマッチすること。
- [x] カラムに `COLLATE NOCASE` が設定されている場合、明示指定なしでも大文字小文字不問で検索できること。
- [x] `COLLATE RTRIM` で末尾スペースの差分を無視して一致判定されること。
- [x] `ORDER BY name COLLATE NOCASE ASC` で意図通り大文字小文字無視順でソートされること。
- [x] `tests/database/sql/test_sql_engine.py` に単体・統合テストを追加し PASS すること。
- [x] `make format`, `make static_analysis` (Rank A, mypy --strict) が PASS すること。
