---
ID: 282
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] SQLite パリティ フェーズ4: DML 実行時の制約バリデーション（PRIMARY KEY 重複 ＆ NOT NULL 制約違反時の IntegrityError 送出）の実装 (ID: 282)

## 1. 概要 / Summary
Pure Python RDBMS (`src/database`) において、現在 DML（INSERT / UPDATE）実行時に `PRIMARY KEY` (UNIQUE) 制約および `NOT NULL` 制約の厳格なリアルタイム検証が行われておらず、制約違反となる行もそのまま受容（正常終了）されてしまっている。
本タスクでは、テーブルカタログ定義（`TableCatalog`）に基づき、PRIMARY KEY 重複および NOT NULL 制約違反を即座に検知して SQLite3 と完全互換のエラーメッセージを持つ `SQLIntegrityError` を送出し、DB-API 2.0 ドライバ層で `IntegrityError` として送出する制約検証エンジンを実装する。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-05-01-sql_syntax_and_specification_support_matrix.md](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
- 監査レポート: [pure_python_db_vs_sqlite3_differential_report.md](../audits/pure_python_db_vs_sqlite3_differential_report.md)
- 関連標準: PEP 249 (Python Database API Specification v2.0) - `IntegrityError`
- 前提Issue: [281-sqlite-parity-phase3-set-operations-and-from-subqueries.md](closed/281-sqlite-parity-phase3-set-operations-and-from-subqueries.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py) (制約バリデーションおよび `SQLIntegrityError` 定義・送出)
- [x] [src/database/ipc/driver.py](../../src/database/ipc/driver.py) (`SQLIntegrityError` から `IntegrityError` へのマッピング伝播)
- [x] [tests/database/compatibility/test_sqlite3_differential.py](../../tests/database/compatibility/test_sqlite3_differential.py) (制約違反の単体テスト)
- [x] [scripts/compare_sqlite3_differential.py](../../scripts/compare_sqlite3_differential.py) (差分監査ハーネス)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/282-sqlite-parity-dml-constraint-validation`

1. **例外クラスの定義**:
   - `src/database/sql/executor.py` に `SQLIntegrityError(SQLExecutionError)` を定義。
2. **制約バリデーションロジックの実装**:
   - `_validate_not_null_constraints(table: TableCatalog, row: Dict[str, Any]) -> None`: 各列の `not_null` / `nullable=False` を検査し、違反時は `SQLIntegrityError(f"NOT NULL constraint failed: {table.name}.{col.name}")` を送出。
   - `_validate_unique_and_pk_constraints(table: TableCatalog, row: Dict[str, Any]) -> None`: PRIMARY KEY または UNIQUE 列について既存行との重複を検査し、重複時は `SQLIntegrityError(f"UNIQUE constraint failed: {table.name}.{col.name}")` を送出。
   - INSERT 処理パイプライン（`_insert_non_vector_row` 等）で `_apply_column_defaults` / `_apply_type_coercion` の直後に上記バリデーションを実行。
3. **ドライバ層での例外マッピング**:
   - `src/database/ipc/driver.py` の `_execute_query` および `Cursor.execute` において、`SQLIntegrityError` または `error_type == "IntegrityError"` を検知した場合に `IntegrityError` を送出するように拡張。
4. **Xenon / Radon 品質ゲート遵守**:
   - すべての新規・改修関数で Cyclomatic Complexity Rank A (<= 5) を維持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `INSERT INTO unique_test VALUES (1, 'another@example.com')` (PK重複) で `IntegrityError: UNIQUE constraint failed: unique_test.id` が送出されること
- [x] `INSERT INTO unique_test VALUES (2, NULL)` (NOT NULL違反) で `IntegrityError: NOT NULL constraint failed: unique_test.email` が送出されること
- [x] 既存の正常系 INSERT / UPDATE / UPSERT が 100% 正常動作しリグレッションがないこと (全324テストPASS)
- [x] `make check_format` および `make static_analysis` (Xenon Rank A, mypy --strict) が 100% PASS すること

---

## 6. 計測結果 (Verification Results)
- `Duplicate Primary Key Violation`: `BOTH_ERROR` (Py=IntegrityError: UNIQUE constraint failed: unique_test.id, Sq=IntegrityError: UNIQUE constraint failed: unique_test.id - 完全一致)
- `NOT NULL Violation`: `BOTH_ERROR` (Py=IntegrityError: NOT NULL constraint failed: unique_test.email, Sq=IntegrityError: NOT NULL constraint failed: unique_test.email - 完全一致)
- 全 79 テスト中、制約違反 2 件が SQLite3 と完全同一のエラー型・メッセージで `BOTH_ERROR`（両者正当拒絶）に合流。
