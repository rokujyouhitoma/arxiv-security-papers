---
ID: 381
種別: Optimization
優先度: High
ステータス: Closed
---

# [OPT/ENH] SQL プリペアドステートメント構文木キャッシュ (AST Parameterized Cache) の導入と PEG パースオーバーヘッドの削減 (ID: 381)

## 1. 概要 / Summary

PyNYTProf による SQLite 差分テスト（`scripts/compare_sqlite3_differential.py`）の計測において、SQL クエリ全体の処理時間約 6.0 秒のうち、**構文解析（`SQLParser.parse`）だけで 5,064.74 ms (84.7%)** を消費していることが判明した。
主な原因は以下の通りであった：
1. `Cursor.execute(sql, params)` がプレースホルダ `?` を実行前にリテラル値へ文字列置換（`_bind_params`）しているため、実行クエリ文字列が毎回ユニークとなり、`parse_sql` に付与された `@lru_cache(maxsize=1024)` が **100% キャッシュミス (Hits: 0)** していた。
2. 同一の SQL テンプレート（例: `INSERT INTO t (a, b) VALUES (?, ?)` や `SELECT ... WHERE id = ?`）であっても、パラメータ値が変わるたびに Packrat PEG パーサの全探索・構文木生成がゼロから実行され、1,000 件の SELECT 実行だけで **7.14 秒** も浪費していた。
3. `SQLExecutor.execute` がグローバルの `@lru_cache` 付き `parse_sql` ではなく、インスタンスローカルな `self.parser.parse(sql)` を直接呼び出していたため、キャッシュ機構が一切バイパスされていた。
4. `src/core/structures/peg.py` 内の `_is_ignorable_expected_token` において、`any(stripped.startswith(p) for p in _IGNORABLE_PREFIXES)` というジェネレータ内包表記がトークン毎に走っており、不要なイテレータ割り当てが発生していた。

本 Issue では、未束縛 SQL テンプレートをそのまま構文木（AST）として LRU キャッシュし、実行時にパラメータを安全・高速に適用するアーキテクチャへ移行するとともに、マイクロ最適化を実施した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (SQL Compiler / Parser Layer)
  - `outputs/profiling/sqlite3_diff.out` (PyNYTProf 計測データ)
  - `src/database/ipc/driver.py` (`Cursor.execute`, `executemany`, `Connection._execute_query`)
  - `src/database/sql/parser.py` (`parse_sql`, `SQLParser`)
  - `src/database/sql/executor.py` (`SQLExecutor.execute`, `execute_statement`, `_bind_statement_params`)
  - `src/core/structures/peg.py` (`_is_ignorable_expected_token`)
  - `scripts/benchmark_parameterized_query.py` (定量ベンチマーク測定スクリプト)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/peg.py`](file:///workspace/arxiv-security-papers/src/core/structures/peg.py) (`_is_ignorable_expected_token` の高速タプルマッチ化)
- [x] [`grammars/sql_expr.peg`](file:///workspace/arxiv-security-papers/grammars/sql_expr.peg) (`placeholder_lit` の PEG 文法定義)
- [x] [`src/database/sql/generated_sql_expr_parser.py`](file:///workspace/arxiv-security-papers/src/database/sql/generated_sql_expr_parser.py) (AOT 再コンパイル)
- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`SQLExecutor.execute`, `_bind_statement_params`, `_extract_field_value` ファストパス)
- [x] [`src/database/ipc/driver.py`](file:///workspace/arxiv-security-papers/src/database/ipc/driver.py) (`Cursor.execute`, `executemany`, `_execute_query`)
- [x] [`scripts/benchmark_parameterized_query.py`](file:///workspace/arxiv-security-papers/scripts/benchmark_parameterized_query.py) (ベンチマーク)
- [x] [`tests/database/test_pep249_interface.py`](file:///workspace/arxiv-security-papers/tests/database/test_pep249_interface.py)
- [x] [`scripts/compare_sqlite3_differential.py`](file:///workspace/arxiv-security-papers/scripts/compare_sqlite3_differential.py)

---

## 4. 実装結果と事前・事後計測値 / Results & Benchmarks

Target Branch: `opt/381-sql-parameterized-ast-cache`

### 4.1. 性能計測比較 (1,000 rows, :memory:)

| 項目 | 修正前 (Baseline) | 修正後 (Optimized) | 改善率 / 高速化倍率 |
| :--- | :--- | :--- | :--- |
| **INSERT 1,000件 所要時間** | 0.3428 秒 (2,916.9 ops/s) | **0.1091 秒 (9,168.7 ops/s)** | **3.14倍 高速化 (68.2% 時間短縮)** |
| **SELECT 1,000件 所要時間** | 7.1391 秒 (140.1 ops/s) | **2.6543 秒 (376.8 ops/s)** | **2.69倍 高速化 (62.8% 時間短縮)** |
| **executemany 1,000件 所要時間** | 0.3895 秒 (2,567.3 ops/s) | **0.1047 秒 (9,550.7 ops/s)** | **3.72倍 高速化 (73.1% 時間短縮)** |
| **parse_sql Cache Hits** | 0 回 (0.0% ヒット率) | **2,997 回 (99.83% ヒット率)** | **完全キャッシュ有効化** |
| **parse_sql Cache Misses** | 0 回 | 5 回 | - |

### 4.2. 実施したコア最適化

1. **`_is_ignorable_expected_token` の高速化 ([`peg.py`](file:///workspace/arxiv-security-papers/src/core/structures/peg.py))**:
   - `any(stripped.startswith(p) for p in _IGNORABLE_PREFIXES)` を `stripped.startswith(_IGNORABLE_PREFIXES)` に変更し、Python の C レベルタプルマッチを活用してイテレータ生成コストを全廃。
2. **PEG 文法へのプレースホルダ構文追加と AOT コンパイル ([`sql_expr.peg`](file:///workspace/arxiv-security-papers/grammars/sql_expr.peg))**:
   - `placeholder_lit <- "?" { return LiteralExpr("?") }` を定義し、`WHERE col = ?` を文法エラーなく PEG パース可能化。
3. **`SQLExecutor.execute` での `parse_sql` LRU キャッシュ統合 & AST バインド ([`executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py))**:
   - `stmt = parse_sql(sql)` を利用し、同一 SQL 文字列に対する PEG パースを 2 回目以降 0ms（LRU キャッシュ取得）化。
   - `_bind_statement_params` により AST スロット（`where_clauses`, `values`, `rows_values`, `assignments` 等）へパラメータをインプレース注入。クォート文字列内の `'?'` を誤置換するリスクを完全排除。
   - `_extract_field_value` に `if expr in record: return record[expr]` 直通ファストパスを導入し、SELECT 時の正規表現評価を大幅削減。
4. **`Cursor.execute` / `executemany` の連携改善 ([`driver.py`](file:///workspace/arxiv-security-papers/src/database/ipc/driver.py))**:
   - 生の文字列置換を廃止し、クエリテンプレートと `params` シーケンスを直接エグゼキュータに渡すアーキテクチャへ統合。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] パラメータ化クエリの繰り返し実行において、`parse_sql` の LRU キャッシュが機能し、SELECT 1,000 件の所要時間が大幅に短縮（7.14s から 2.65s へ 62.8% 短縮）すること。
- [x] `executemany` においてパースが 1 回のみとなり、スループットが向上（0.3895s から 0.1047s へ 3.72倍高速化）すること。
- [x] SQL 文字列内（クォート文字列内）の `'?'` が誤って置換されないこと。
- [x] 全ての PEP 249 テスト（446 件）および SQLite 差分テスト（75 ケース）が 100% PASS すること。
- [x] `make py_compile`, `make check_format`, `make static_analysis` がすべて PASS すること。
- [x] コード内に `# noqa: E402` などの警告抑制コメントを含めないこと。
