---
ID: 281
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-09-13
---

# [FEAT/ENH] SQLite パリティ フェーズ3 — スタンドアロン集合演算 ＆ FROM句派生サブクエリ (ID: 281)

## 1. 概要 / Summary

Pure Python データベース (`src/database`) と `sqlite3` の差分を縮小するフェーズ3実装。
フェーズ2（Issue #280）で BEHAVIORAL_DIFF を 0件（完全解消）にし、MATCH率を 86.1% (68/79) に到達させた。
本フェーズ3では、残存する `SQLITE-ONLY SUCCESS: 5件` を解消し、MATCH率を **92.4% (73/79)** に向上させた。

対象課題一覧（全5件）:

| # | 課題分類 | テストケース | 現象・エラー | 根本原因 |
| :-: | :--- | :--- | :--- | :--- |
| **1** | 集合演算 | **UNION (Deduplicating)** | `Execution error: Malformed SELECT syntax: SELECT 1 AS x` | `FROM` 句のないスタンドアロン SELECT が単体または集合演算内でパース/実行できない |
| **2** | 集合演算 | **UNION ALL** | 同上 | 同上 |
| **3** | 集合演算 | **INTERSECT** | 同上 | 同上 |
| **4** | 集合演算 | **EXCEPT** | 同上 | 同上 |
| **5** | サブクエリ | **Derived Table in FROM** | `Table '(SELECT * FROM employees WHERE dept_id < 50) sub' does not exist` | `FROM (SELECT ...) alias` のインライン派生テーブルが物理テーブルとして探索される |

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [差分監査レポート](../../audits/pure_python_db_vs_sqlite3_differential_report.md)
  - [DSN-05-01 SQLサポートマトリクス](../../designs/DSN-05-01-sql_syntax_and_specification_support_matrix.md)
  - [フェーズ1 Issue #279](279-sqlite-parity-phase1-rowcount-default-and-numeric-affinity.md)
  - [フェーズ2 Issue #280](280-sqlite-parity-phase2-join-type-coercion-upsert-json.md)
  - 差分測定スクリプト: `scripts/compare_sqlite3_differential.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/sql/ast.py`](../../../src/database/sql/ast.py)
  - `TableRef.subquery` 属性追加
  - `SelectStatement.compounds` 属性追加
- [x] [`src/database/sql/parser.py`](../../../src/database/sql/parser.py)
  - `FROM` 句のない `SELECT <exprs>`（スタンドアロンクエリ）のパース対応
  - `_split_all_top_level_compounds` による左結合（left-associative）複合演算パイプライン分解
  - `_parse_single_table_ref` での `FROM (SELECT ...) alias` 派生テーブル構文解析
- [x] [`src/database/sql/executor.py`](../../../src/database/sql/executor.py)
  - `_get_initial_select_rows` でのスタンドアロン SELECT 評価（空辞書 `[{}]` 生成）
  - `_evaluate_derived_tables` での派生テーブル動的一時テーブル評価
  - `_align_compound_rows` / `_deduplicate_rows` での値タプル重複排除
  - `_apply_compound_operations` での左結合パイプライン評価
- [x] [`tests/database/compatibility/test_sqlite3_differential.py`](../../../tests/database/compatibility/test_sqlite3_differential.py)
  - `test_phase3_standalone_set_ops_and_from_subqueries` 回帰テスト追加 (全9テスト PASS)
- [x] [`docs/audits/pure_python_db_vs_sqlite3_differential_report.md`](../../../docs/audits/pure_python_db_vs_sqlite3_differential_report.md)
  - フェーズ3 計測結果（Before vs After）の記録

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/281-sqlite-parity-phase3`

### 1. スタンドアロン SELECT (FROM 句なし) のサポート
- パーサーで `FROM` 句のないクエリを検知し、`table_name = ""` の `SelectStatement` を生成。
- エグゼキュータで `table_name` が空の場合、単一の空行 `[{}]` から射影式を評価。

### 2. 左結合複合演算子 (UNION / UNION ALL / INTERSECT / EXCEPT)
- `_split_all_top_level_compounds` により、トップレベルの演算子を左から順に分解して `stmt.compounds` に登録。
- エグゼキュータが左から順に順次演算（畳み込み）を適用し、列キーのアラインメントおよび値タプルによる重複判定を実施。

### 3. FROM 句派生テーブル (Derived Table) のオンザフライ解決
- `_parse_single_table_ref` で `(SELECT ...) alias` を検知し、内部クエリを再帰パース。
- `_evaluate_derived_tables` で外部クエリ実行前に内部クエリを実行し、`temp_tables[alias]` に登録。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `make differential_audit` で `SQLITE-ONLY SUCCESS` が 5件 → 0件 に解消
- [x] `MATCH / EQUIVALENT >= 92%` (開始時 86.1% / 68件 → 実績 73件 / 79件, 92.4%)
- [x] `BEHAVIORAL_DIFF = 0件` を維持
- [x] `pytest tests/database/compatibility/test_sqlite3_differential.py` 全9テスト PASSED
- [x] `make py_compile` 構文エラー 0件
- [x] `make static_analysis` (black, isort, flake8, mypy) エラー 0件
- [x] 監査レポートおよび設計書への計測結果追記

---

## 6. 計測結果 / Measurement Results

### フェーズ3 開始前 (ベースライン: Phase 2 終了時)

| 指標 | 値 |
|------|-----|
| MATCH / EQUIVALENT | 68 / 79 (86.1%) |
| BEHAVIORAL_DIFF | 0件 (0.0%) |
| SQLITE-ONLY SUCCESS | 5件 (6.3%) |
| PURE PYTHON EXTENSIONS | 5件 (6.3%) |
| BOTH REJECTED (ERRORS) | 1件 (1.3%) |

### フェーズ3 終了後

| 指標 | 値 | 変化 (vs Phase 2) | 総合変化 (vs Baseline) |
|------|-----|-------------------|------------------------|
| **MATCH / EQUIVALENT** | **73 / 79 (92.4%)** | **+5件 (+6.3%)** | **+32件 (+40.5%)** |
| **BEHAVIORAL_DIFF** | **0件 (0.0%)** | **±0件 (0件維持)** | **-27件 (完全解消)** |
| **SQLITE-ONLY SUCCESS** | **0件 (0.0%)** | **-5件 (完全解消)** | **-5件 (完全解消)** |
| **PURE PYTHON EXTENSIONS** | 5件 (6.3%) | ±0件 | ±0件 (独自機能維持) |
| **BOTH REJECTED (ERRORS)** | 1件 (1.3%) | ±0件 | ±0件 (仕様通り) |
| **回帰テスト** | 9 passed | +1テスト追加 | 9テスト全通過 |

**解消された SQLITE-ONLY SUCCESS 詳細 (全5件 MATCH 転換):**

| Test Case | Pure Python 出力 | SQLite 出力 | 判定 |
|-----------|------------------|-------------|:---:|
| **UNION (Deduplicating)** | `[(1,), (2,)]` | `[(1,), (2,)]` | **MATCH** |
| **UNION ALL** | `[(1,), (2,), (1,)]` | `[(1,), (2,), (1,)]` | **MATCH** |
| **INTERSECT** | `[(2,), (3,)]` | `[(2,), (3,)]` | **MATCH** |
| **EXCEPT** | `[(1,), (3,)]` | `[(1,), (3,)]` | **MATCH** |
| **Derived Table in FROM** | `[(10, 2), (20, 1)]` | `[(10, 2), (20, 1)]` | **MATCH** |

