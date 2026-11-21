---
ID: 894
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Implement Pure Scheme Compile-Time PEG Parser Generator (ID: 894)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 3 章に基づき、[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) の Packrat PEG アルゴリズムを Pure Scheme / ULisp マクロ体系へ移植し、宣言的文法定義（`define-grammar`）から手書き並みの高速構文解析ルーチンおよび Stage-Now 評価器へ直結するジェネレータを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ設計書 (第3章 PEG/Packrat 構文解析フロントエンドのゼロコスト自動合成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/workbench/peg.scm](../../ulisp/workbench/peg.scm)
- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm)
- [ ] [ulisp/tests/test_workbench_peg.scm](../../ulisp/tests/test_workbench_peg.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/894-implement-pure-scheme-compile-time-peg-parser-generator`

1. Pure Scheme による PEG コンビネータ（`seq`, `alt`, `star`, `plus`, `opt`, `not-pred`, `and-pred`）およびメモ化 Packrat キャッシュを実装。
2. マクロ `define-grammar` を定義し、静的な文法定義から先頭文字ディスパッチテーブルを持つ再帰下降パーサーコードを自動生成。
3. セマンティックアクションを CPS で直結し、中間 AST ノードをヒープ確保せずに評価器・残余 LIR へストリーミングする zero-allocation モードを実装。
4. 単体テスト `test_workbench_peg.scm` で算術式および文法規則の構文解析精度・性能を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `define-grammar` マクロが宣言的文法定義から正常に Scheme パーサーを生成すること。
- [ ] 中間 AST の不要な割り当てが排除され、構文解析とセマンティクスが直結されること。
- [ ] `make -C ulisp test_workbench_peg` が PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
