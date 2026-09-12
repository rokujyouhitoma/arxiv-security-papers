---
ID: 269
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/DATABASE] SQLite 完全互換化: 生成列 (GENERATED ALWAYS AS) の実装 (ID: 269)

## 1. 概要 / Summary
SQLite 3.31.0+ 仕様 ([sqlite.org/gencol.html](https://sqlite.org/gencol.html)) に準拠した生成列 (`GENERATED ALWAYS AS (expr) [STORED | VIRTUAL]`) を Pure Python SQL Engine (`src/database/sql/`) に実装する。
他カラムの値から決定論的に導出される計算列を定義可能にし、冗長なアプリケーション層計算の排除およびインデックス連携を可能にする。

---

## 2. トレーサビリティ / Traceability
- 準拠仕様: [SQLite Generated Columns](https://sqlite.org/gencol.html)
- 関連設計書:
  - [DSN-05-01 SQL 構文仕様およびサポートマトリクス設計書](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../designs/DSN-14-next_gen_database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/sql/ast.py](../../src/database/sql/ast.py): `ColumnDef` に `generated_expr: Optional[str]` および `is_stored: bool` を追加
- [ ] [src/database/sql/parser.py](../../src/database/sql/parser.py): `GENERATED ALWAYS AS (...) [STORED|VIRTUAL]` のパース実装
- [ ] [src/database/sql/executor.py](../../src/database/sql/executor.py): レコード挿入・更新時の式自動計算および参照解決
- [ ] [tests/database/sql/test_sql_engine.py](../../tests/database/sql/test_sql_engine.py): 単体テスト追加

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/269-implement-sqlite-parity-generated-columns`

1. カラム定義構文で `GENERATED ALWAYS AS (expr)` または `AS (expr)` を認識。
2. `STORED`（永続化）または `VIRTUAL`（読み出し時動的計算）の属性を管理。
3. `INSERT` / `UPDATE` 時に直接値を与えることを禁止し、元カラムの値変化に応じて安全な式評価器で値を自動算出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `col INT GENERATED ALWAYS AS (c1 + c2) STORED` が正しく定義できること。
- [ ] データ挿入時に `col` が自動計算されて格納されること。
- [ ] `col` に対する明示的な `INSERT` / `UPDATE` 試行時にエラーとなること。
- [ ] `tests/database/sql/test_sql_engine.py` にテストを追加し PASS すること。
- [ ] `make format`, `make static_analysis` が PASS すること。
