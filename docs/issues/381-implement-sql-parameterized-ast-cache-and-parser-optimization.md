---
ID: 381
種別: Optimization
優先度: High
ステータス: Open (New)
---

# [OPT/ENH] SQL プリペアドステートメント構文木キャッシュ (AST Parameterized Cache) の導入と PEG パースオーバーヘッドの削減 (ID: 381)

## 1. 概要 / Summary

PyNYTProf による SQLite 差分テスト（`scripts/compare_sqlite3_differential.py`）の計測において、SQL クエリ全体の処理時間約 6.0 秒のうち、**構文解析（`SQLParser.parse`）だけで 5,064.74 ms (84.7%)** を消費していることが判明した。
主な原因は以下の通りである：
1. `Cursor.execute(sql, params)` がプレースホルダ `?` を実行前にリテラル値へ文字列置換（`_bind_params`）しているため、実行クエリ文字列が毎回ユニークとなり、`parse_sql` に付与された `@lru_cache(maxsize=1024)` が **100% キャッシュミス** している。
2. 同一の SQL テンプレート（例: `INSERT INTO t (a, b) VALUES (?, ?)`）であっても、パラメータ値が変わるたびに Packrat PEG パーサの全探索・構文木生成がゼロから実行されている。
3. `src/core/structures/peg.py` 内の `_is_ignorable_expected_token` におけるジェネレータ多重評価等のマイクロオーバーヘッド。

本 Issue では、プレースホルダを含む未束縛 SQL テンプレートをそのままパースして構文木（AST）を LRU キャッシュし、実行時にパラメータを AST または実行エンジンへ安全にバインドするアーキテクチャへの移行を実施する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (SQL Compiler / Parser Layer)
  - `outputs/profiling/sqlite3_diff.out` (PyNYTProf 計測データ)
  - `src/database/ipc/driver.py` (`Cursor.execute`, `_bind_params`)
  - `src/database/sql/parser.py` (`parse_sql`)
  - `src/core/structures/peg.py` (Packrat PEG Engine)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/ipc/driver.py`](file:///workspace/arxiv-security-papers/src/database/ipc/driver.py) (`Cursor.execute`, `executemany`, `_bind_params`)
- [ ] [`src/database/sql/parser.py`](file:///workspace/arxiv-security-papers/src/database/sql/parser.py) (`SQLParser.parse`, `parse_sql`, `clear_sql_parser_caches`)
- [ ] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`SQLExecutor.execute`, `execute_statement`)
- [ ] [`src/core/structures/peg.py`](file:///workspace/arxiv-security-papers/src/core/structures/peg.py) (`_is_ignorable_expected_token`)
- [ ] [`tests/database/test_pep249_interface.py`](file:///workspace/arxiv-security-papers/tests/database/test_pep249_interface.py)
- [ ] [`tests/database/test_sql_subsystems_benchmark.py`](file:///workspace/arxiv-security-papers/tests/database/test_sql_subsystems_benchmark.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `opt/381-sql-parameterized-ast-cache`

1. `Cursor.execute` において、`_bind_params` による生の文字列置換を廃止し、元の SQL テンプレート（`?` を含むクエリ）と `params` タプルを分離して保持。
2. 未束縛の SQL テンプレートに対して `parse_sql` を呼び出し、パラメータ化された AST（`InsertStatement`, `SelectStatement` 等）を LRU キャッシュから取得。
3. パラメータ値のバインドを実行時（`SQLExecutor.execute` / `execute_statement`）に AST の各スロットへ注入する仕組みを実装。
4. `executemany` において、AST パースを 1 回のみ行い、パラメータループでバインド＆実行のみを繰り返す構造に最適化。
5. `src/core/structures/peg.py` の `_is_ignorable_expected_token` のジェネレータ内包表記をタプル `startswith` に置換して高速化。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] パラメータ化クエリの繰り返し実行において、`parse_sql` の LRU キャッシュヒット率が 90% 以上になること。
- [ ] `executemany` のスループットが劇的に向上（パース回数が 1 回に削減）すること。
- [ ] SQL 文字列内での `?` の誤置換（クォート文字列内の `?` を置換してしまう不具合）が防止されること。
- [ ] 全ての PEP 249 テストおよび SQLite 差分テストが 100% PASS すること。
- [ ] `make py_compile`, `make check_format`, `make static_analysis` が PASS すること。
