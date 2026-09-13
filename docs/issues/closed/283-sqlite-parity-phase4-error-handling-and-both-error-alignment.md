---
ID: 283
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] SQLite パリティ フェーズ4: 異常系エラーハンドリング統一 (無効なROLLBACKのOperationalError化) および BOTH_ERROR 評価確立 (ID: 283)

## 1. 概要 / Summary
Pure Python RDBMS (`src/database`) において、アクティブなトランザクションが存在しない状態で `ROLLBACK` を発行した場合、SQLite3 は `OperationalError: cannot rollback - no transaction is active` を返却するのに対し、Pure Python は現在 `ProgrammingError: Execution error: No active transaction to rollback` を返却している。
本タスクでは、トランザクションマネージャおよびドライバ層における例外型の整合性を高め、無効な ROLLBACK に対して `OperationalError` を送出するよう統一する。さらに、Issue 282 で実装される制約違反と合わせ、差分監査ハーネスにおける `BOTH_ERROR`（両者正当拒絶）分類の確立と計測レポートを作成する。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-05-01-sql_syntax_and_specification_support_matrix.md](../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
- 監査レポート: [pure_python_db_vs_sqlite3_differential_report.md](../audits/pure_python_db_vs_sqlite3_differential_report.md)
- 関連標準: PEP 249 (Python Database API Specification v2.0) - `OperationalError`
- 前提Issue: [282-sqlite-parity-phase4-dml-constraint-validation.md](282-sqlite-parity-phase4-dml-constraint-validation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/sql/executor.py](../../src/database/sql/executor.py) (`SQLOperationalError` の定義と送出)
- [x] [src/database/ipc/driver.py](../../src/database/ipc/driver.py) (`SQLOperationalError` から `OperationalError` へのマッピング)
- [x] [tests/database/compatibility/test_sqlite3_differential.py](../../tests/database/compatibility/test_sqlite3_differential.py) (異常系トランザクションエラーテスト)
- [x] [scripts/compare_sqlite3_differential.py](../../scripts/compare_sqlite3_differential.py) (差分監査レポート出力)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/283-sqlite-parity-error-handling-and-both-error`

1. **例外クラスの定義**:
   - `src/database/sql/executor.py` に `SQLOperationalError(SQLExecutionError)` を定義。
2. **無効な ROLLBACK の OperationalError 化**:
   - トランザクションが存在しない状態での `ROLLBACK` 時、`SQLOperationalError("cannot rollback - no transaction is active")` を送出。
3. **ドライバ層での OperationalError 伝播**:
   - `src/database/ipc/driver.py` で `SQLOperationalError` または `error_type == "OperationalError"` を `OperationalError` として再送出。
4. **差分比較ハーネスにおける検証**:
   - `scripts/compare_sqlite3_differential.py` を実行し、制約違反2件および無効ROLLBACK1件の計3件が `BOTH_ERROR` として分類・評価されることを確認。
5. **計測結果レポート**:
   - フェーズ4の開始前・終了後の差分指標表を監査レポートおよび設計書に追記。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] アクティブなトランザクションがない状態での `ROLLBACK` 実行時に `OperationalError: cannot rollback - no transaction is active` が送出されること
- [x] `scripts/compare_sqlite3_differential.py` において、`BOTH_ERROR` が 1件から 3件へ増加し、`PY_ONLY_SUCCESS` が 5件から 3件（VECTOR独自拡張2件 + BEGIN 1件）へ減少すること
- [x] `BEHAVIORAL_DIFF: 0件`、`SQLITE_ONLY: 0件` を完全維持すること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること

---

## 6. 計測結果 (Verification Results)
- `ROLLBACK Transaction`: `BOTH_ERROR` (Py=OperationalError: cannot rollback - no transaction is active, Sq=OperationalError: cannot rollback - no transaction is active - 完全一致)
- 全 79 テスト中、`BOTH_ERROR` は 3 件 (3.8%)、`BEHAVIORAL_DIFF` は 0 件 (0.0%)、`SQLITE_ONLY` は 0 件 (0.0%)、`MATCH` は 73 件 (92.4%)。
