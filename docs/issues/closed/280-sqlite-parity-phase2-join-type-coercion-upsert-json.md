---
ID: 280
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-09-13
---

# [FEAT/ENH] SQLite パリティ フェーズ2 — JOIN投影・型強制・UPSERT式評価・JSON ->> (ID: 280)

## 1. 概要 / Summary

Pure Python データベース (`src/database`) と `sqlite3` の挙動差分を縮小するフェーズ2実装。
フェーズ1（Issue #279）で MATCH率を 51.9% → 75.9% に向上させた後、残存する 8件の `BEHAVIORAL_DIFF` を解消する。

対象4件の根本原因と修正方針:

| Issue | 現象 | 根本原因 |
|-------|------|----------|
| **A** | JOIN 列の key collision | `_project_row` が同名短縮キーを上書き |
| **B** | IS NULL / TYPEOF / 算術の型不一致 | INSERT時に全値が文字列として格納される |
| **C** | UPSERT SET RHS 式が未評価 | `_handle_conflict` が raw 文字列をそのまま書き込む |
| **D** | JSON `->>` 演算子が None を返す | `_extract_json_val` が `$.key` 形式のパスを解析できない |

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [差分監査レポート](../../audits/pure_python_db_vs_sqlite3_differential_report.md)
  - [DSN-05-01 SQLサポートマトリクス](../../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [フェーズ1 Issue #279](279-sqlite-parity-phase1-rowcount-default-and-numeric-affinity.md)
  - 差分測定スクリプト: `scripts/compare_sqlite3_differential.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/sql/executor.py`](../../../src/database/sql/executor.py)
  - `_extract_json_val` — JSON `$.key` パス正規化
  - `_extract_field_value` — `NULL` キーワードを `None` として評価
  - `_project_row` — 重複キー時の衝突回避ロジック
  - `_handle_conflict` — UPSERT SET 式の RHS 評価
  - `_coerce_value_to_type` — 新規追加: 型強制ヘルパー
  - `_apply_type_coercion` — 新規追加: INSERT時型強制適用
  - `_build_insert_row_dicts` — 型強制を呼び出すよう更新
- [x] [`tests/database/compatibility/test_sqlite3_differential.py`](../../../tests/database/compatibility/test_sqlite3_differential.py)
  - `test_phase2_join_type_coercion_upsert_json` — 新規回帰テスト追加

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/280-sqlite-parity-phase2`

### Issue A: JOIN カラム投影キー衝突

`_project_row` に `used_keys: set[str]` を導入し、同じ短縮名が2回登場した場合は元の修飾名（例: `e.name`）をキーとして使用することで、`dict` のキー衝突による値上書きを防ぐ。

### Issue B: INSERT時の型強制

`_coerce_value_to_type(val, data_type)` を新規実装し、`_build_insert_row_dicts` で各行に適用。

- `INT`/`INTEGER` 系 → `int(val)`
- `REAL`/`FLOAT` 系 → `float(val)`
- `'NULL'` 文字列 → `None`

`_extract_field_value` で `expr.upper() == "NULL"` を直接 `None` に評価。

### Issue C: UPSERT SET RHS 式評価

`_handle_conflict` で `upsert_update_set` の各値を `_extract_field_value(ctx, expr_val)` で評価してから格納。

### Issue D: JSON `->>` パス正規化

`_extract_json_val` で `$.key` → `key` への正規化を追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `make differential_audit` で `BEHAVIORAL_DIFF = 0` 件
- [x] `MATCH / EQUIVALENT >= 86%` (開始時 75.9%)
- [x] `pytest tests/database/compatibility/test_sqlite3_differential.py` — 8テスト全PASSED
- [x] `make py_compile` — 構文エラー 0件
- [x] `make static_analysis` — lintエラー新規追加なし
- [x] `make format` — フォーマット適合

---

## 6. 計測結果 / Measurement Results

### フェーズ2 開始前 (ベースライン)

| 指標 | 値 |
|------|-----|
| MATCH / EQUIVALENT | 60 / 79 (75.9%) |
| BEHAVIORAL_DIFF | 8件 |
| BOTH_ERROR | 11件 |

**BEHAVIORAL_DIFF 詳細:**

| Test Case | Pure Python | SQLite |
|-----------|-------------|--------|
| INNER JOIN with ON | `[('Security',), ...]` | `[('Alice', 'Security'), ...]` |
| LEFT JOIN with NULL | `[('Security',), ...]` | `[('Alice', 'Security'), ...]` |
| Select IS NULL | `[]` | `[(1,)]` |
| Select IS NOT NULL | `[('1',), ('2',), ('3',)]` | `[(1,), (3,)]` |
| Arithmetic with NULL | `[('1', ...)]` | `[(1, ...)]` |
| TYPEOF builtin | all `'text'` | `'integer'/'null'/'real'` |
| Verify Upsert Result | `[('hits', 'cnt + 10')]` | `[('hits', 11)]` |
| JSON Arrow Operator ->> | `[(1, None)]` | `[(1, 'alice')]` |

### フェーズ2 終了後

| 指標 | 値 | 変化 |
|------|-----|------|
| MATCH / EQUIVALENT | 68 / 79 (86.1%) | **+10.2%** |
| BEHAVIORAL_DIFF | **0件** | **-8件** |
| BOTH_ERROR | 11件 | 変化なし |
| 回帰テスト | 8 passed | +1テスト追加 |
