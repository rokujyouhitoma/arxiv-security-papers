---
ID: 946
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT/ENH] SQL 実行器における式文字列のレコード毎再解析の解消と AST 事前コンパイル化 (ID: 946)

## 1. 概要 / Summary

アプリケーション層の SQL 実行器（[executor.py](../../src/database/sql/executor.py) の `_eval_core_expr_features` / `_eval_extended_ops` / `_eval_case_condition_match` 等）が、SQL 式の文字列をレコード評価ごとに再解析（文字列分割・正規表現マッチ等）しており、走査件数増加時の CPU オーバーヘッド要因となっている。

クエリ実行前に式を [expr_parser.py](../../src/database/sql/expr_parser.py) による型付き AST へ 1 度だけ事前コンパイルし、レコード評価ループ内ではコンパイル済み AST（または評価クロージャ）を直接評価する構成へ改善する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [executor.py](../../src/database/sql/executor.py)
  - [expr_parser.py](../../src/database/sql/expr_parser.py)
  - [parser.py](../../src/database/sql/parser.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [executor.py](../../src/database/sql/executor.py)
- [ ] [expr_parser.py](../../src/database/sql/expr_parser.py)
- [ ] [parser.py](../../src/database/sql/parser.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/946-precompile-sql-expressions`

1. `executor.py` 内でレコードごとに式文字列を再解析している箇所をすべて特定する。
2. クエリ単位で 1 度だけ `expr_parser.py` により AST 化（および評価クロージャ化）し、全レコードに対して事前コンパイル済み式を使い回すよう改修する（詳細は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 同一クエリ内のレコード走査中に SQL 式文字列の再解析が発生しないこと。
- [ ] SQL 関連既存テストおよび `make py_compile && make static_analysis` が PASS すること（詳細ゲートは `polish-issue` 時に確定）。
