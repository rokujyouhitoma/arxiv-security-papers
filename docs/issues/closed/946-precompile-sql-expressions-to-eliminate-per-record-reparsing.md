---
ID: 946
種別: Feature
優先度: Low
ステータス: Closed
---

# [FEAT/ENH] SQL 実行器における式文字列のレコード毎再解析の解消と AST 事前コンパイル化 (ID: 946)

## 1. 概要 / Summary

アプリケーション層の SQL 実行器（[executor.py](../../../src/database/sql/executor.py)）が、同一クエリのレコード走査ループ内で SQL 式文字列を毎行再解析（正規表現マッチ・文字列分割・PEG パーサ再呼び出し）しており、走査件数の増加に比例して CPU オーバーヘッドが増大していた。

### 解決したボトルネック
1. **`_extract_field_value` の毎行文字列解析**:
   - `_extract_concat_expr`（`split("||")`）、`_eval_core_expr_features`（`CASE` / 関数呼出 / 比較の `re.match`/`re.compile` および PEG `_split_comma_expressions`）、`_eval_extended_ops`（算術 `re.match`・JSON `split("->")`）を廃止し、事前コンパイル済みクロージャ評価へ一本化した。
2. **全ホットループにおける事前コンパイル化**:
   - `SELECT` 射影（`compile_projection` による `AS alias` 事前解析と出力キー解決）
   - `WHERE` / `JOIN ON` フィルタ（`compile_where_clauses`、`LIKE` 正規表現・`IN` `frozenset`・期待値解決の事前コンパイル）
   - `GROUP BY` / 集約（`_cluster_rows`, `_agg_count`, `_agg_numeric_list`, `_agg_min_max` の二重評価解消, `_compute_agg_group_concat`）
   - `HAVING`（`compile_having_expr`）
   - `ORDER BY`（`_sort_and_paginate`, `_sort_custom_collate`, `_sort_and_limit_indices`）
   - Hash Join キー抽出、Nested Loop Join、`UPDATE SET`、生成列、TVF、UPSERT
3. **PEG 文法・AST の拡張**:
   - [sql_expr.peg](../../../tools/grammars/sql_expr.peg) に文字列連結演算子 `||`、非アンコート JSON 抽出 `->`（`ColumnRefExpr.json_unquote`）、および複数階層ドット修飾識別子（`schema.table.column`）を追加し、AOT パーサ（[generated_sql_expr_parser.py](../../../src/database/sql/generated_sql_expr_parser.py)）を再生成した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [executor.py](../../../src/database/sql/executor.py)
  - [expr_compiler.py](../../../src/database/sql/expr_compiler.py)
  - [expr_parser.py](../../../src/database/sql/expr_parser.py)
  - [generated_sql_expr_parser.py](../../../src/database/sql/generated_sql_expr_parser.py)
  - [sql_expr.peg](../../../tools/grammars/sql_expr.peg)
  - [parser.py](../../../src/database/sql/parser.py)
  - [ast.py](../../../src/database/sql/ast.py)
  - [functions.py](../../../src/database/sql/functions.py)
  - [test_sql_expr_benchmark.py](../../../tests/database/test_sql_expr_benchmark.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [sql_expr.peg](../../../tools/grammars/sql_expr.peg) (`||` 文字列連結演算子、`->` 非アンコート JSON 抽出、`schema.table.column` 複数階層識別子の文法追加)
- [x] [generated_sql_expr_parser.py](../../../src/database/sql/generated_sql_expr_parser.py) (`make compile_grammars` による AOT パーサ再生成)
- [x] [expr_parser.py](../../../src/database/sql/expr_parser.py) (`ColumnRefExpr` への `json_unquote: bool = True` 追加と `to_sql()` 対応)
- [x] [ast.py](../../../src/database/sql/ast.py) (`SQLExecutionError` / `SQLIntegrityError` / `SQLOperationalError` の共通定義)
- [x] [expr_compiler.py](../../../src/database/sql/expr_compiler.py) (新規作成: `SQLExpr` → 評価クロージャ事前コンパイラ、`compile_projection`、`compile_where_clauses`、`compile_having_expr`、LRU キャッシュ)
- [x] [executor.py](../../../src/database/sql/executor.py) (全ホットループの事前コンパイル化、`_agg_min_max` 重複評価修正、`_extract_field_value` のコンパイラ委譲)
- [x] [parser.py](../../../src/database/sql/parser.py) (`clear_sql_parser_caches()` へのコンパイラキャッシュクリア統合)
- [x] [test_expr_compiler.py](../../../tests/database/sql/test_expr_compiler.py) (新規作成: 意味論同値テスト、非再解析スパイ検証、セキュリティ境界テスト、性能ベンチマーク)
- [x] [test_sql_expr_peg.py](../../../tests/database/test_sql_expr_peg.py) (`||` / `->` / `schema.table.col` の PEG パーステスト追加)
- [x] [test_sql_expr_aot.py](../../../tests/database/test_sql_expr_aot.py) (`||` / `->` / `schema.table.col` の AOT パーステスト追加)

---

## 4. セキュリティ要件と脅威対策 / Security Requirements & Threat Mitigations

1. **CWE-400 (ReDoS — `LIKE` パターン正規表現)**:
   - `compile_like_pattern` にて連続する非エスケープ `%` を単一 `%` へ畳み込み（`_MULTI_PCT_RE`）、`.*.*.*` 連鎖による指数的バックトラックを防止。パターン長上限（`MAX_LIKE_PATTERN_LEN = 1024`）超過時は `SQLExecutionError` を送出。
2. **CWE-674 (Uncontrolled Recursion — 過度に深い式 AST)**:
   - `_compile_node` に再帰深度上限ガード（`MAX_EXPR_AST_DEPTH = 64`）を実装し、超過時は `SQLExecutionError` を送出。
3. **CWE-400 (メモリ枯渇 — コンパイルキャッシュ肥大化)**:
   - `compile_sql_expr`（`maxsize=2048`）、`compile_like_pattern`（`maxsize=1024`）、`compile_having_expr`（`maxsize=1024`）に上限付き LRU キャッシュを適用し、`clear_sql_parser_caches()` で一括解放可能にした。
4. **CWE-94 / CWE-89 (動的コード生成・実行の完全排除)**:
   - `eval()` / `exec()` / 動的 Python ソース文字列生成は一切使用せず、型付き `SQLExpr` AST ノードに対する静的ディスパッチの純粋クロージャ合成のみで構成した。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/946-precompile-sql-expressions`

1. [sql_expr.peg](../../../tools/grammars/sql_expr.peg) と [expr_parser.py](../../../src/database/sql/expr_parser.py) を拡張し、`make compile_grammars` で [generated_sql_expr_parser.py](../../../src/database/sql/generated_sql_expr_parser.py) を再生成。
2. [expr_compiler.py](../../../src/database/sql/expr_compiler.py) を新規作成し、`SQLExpr`・射影・`WHERE`・`HAVING` の事前コンパイラおよびセキュリティガードを実装。
3. [executor.py](../../../src/database/sql/executor.py) の全ホットループへ事前コンパイル評価クロージャを組み込み、旧来の毎行正規表現パース関数群を削除。
4. [parser.py](../../../src/database/sql/parser.py) の `clear_sql_parser_caches()` に `clear_sql_expr_compiler_cache()` を接続。
5. [test_expr_compiler.py](../../../tests/database/sql/test_expr_compiler.py)・[test_sql_expr_peg.py](../../../tests/database/test_sql_expr_peg.py)・[test_sql_expr_aot.py](../../../tests/database/test_sql_expr_aot.py) を追加し、品質ゲートを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] [sql_expr.peg](../../../tools/grammars/sql_expr.peg) に `||` および `->` が追加され、`make compile_grammars` 後の [generated_sql_expr_parser.py](../../../src/database/sql/generated_sql_expr_parser.py) で既存＋新規パーステストが全 PASS する。
- [x] [expr_compiler.py](../../../src/database/sql/expr_compiler.py) が実装され、同一クエリ内の N レコード走査（N=1,000）中に SQL 式文字列の再解析（`parse_sql_expr` / `re.compile`）がレコード数に比例して発生しないことがスパイテストで確認されている。
- [x] [executor.py](../../../src/database/sql/executor.py) の全ホットパス（`SELECT` 射影、`WHERE`、`JOIN ON`、`GROUP BY`/集約、`HAVING`、`ORDER BY`、Hash Join、`UPDATE SET`、生成列）が事前コンパイル済みクロージャを使用し、`_agg_min_max` の重複評価が解消されている。
- [x] セキュリティ境界テスト（AST 深度上限超過、`LIKE` 連続 `%` ReDoS 防御・パターン長制限、キャッシュクリア、`eval`/`exec` 非使用）が全 PASS する。
- [x] `tests/database/` 全テストスイートが 100% PASS する。
- [x] `make check_format` および `make static_analysis`（`isort`, `black`, `flake8`, `radon`, `xenon` Rank A, `mypy --strict`, `py_compile`）が 0 エラーで PASS する。
- [x] 相対リンクのみ・絶対パス 0 件であることを検証済み。

---

## 7. 検証結果 / Verification Results

- **非再解析スパイ検証（1,000 行スキャン `SELECT ... CASE ... || ... WHERE ... LIKE ... ORDER BY`）**:
  - `parse_sql_expr` 呼び出し回数: **6 回**（クエリ内の式数に応じた O(1)、レコード数 1,000 に対する再解析 0 回）
- **性能ベンチマーク（2,000 行複雑クエリ走査）**:
  - 実行時間: **15.37 ms**（目標 < 500 ms に対して余裕で達成）
- **テスト結果**:
  - `PYTHONPATH=src .venv/bin/pytest tests/database/ -v`: **455 passed, 7 deselected**（0 failed）
- **静的解析・フォーマット**:
  - `make check_format` (`isort --check-only`, `black --check`, `flake8`): **PASS**
  - `make static_analysis` (`radon`, `xenon --max-absolute A`, `mypy --strict src` 618 files, `py_compile`): **PASS**
