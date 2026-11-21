---
ID: 907
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Support CPython PEG Grammar Specification in src/core/peg (ID: 907)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) に基づき、`src/core/peg`（Packrat PEG コンパイラおよびランタイム）において、CPython 公式の PEG 文法仕様（PEP 617 / [Grammar/python.gram](https://github.com/python/cpython/tree/main/Grammar)）をファーストクラスでサポートする機能拡張を実装する。

現在、`src/core/peg/compiler/parser.py` は Bryan Ford POPL '04 記法（`<-` によるルール定義、`/` による選択、`name:expr` による変数束縛）を中心に対応している。本 Issue では、CPython の標準 PEG 構文であるコロンによるルール定義（`rule: e1 | e2`）、イコールによる変数束縛（`name=expr` や `(name=expr)`）、カット演算子（`~`）、角括弧によるオプショナル（`[expr]`）、セパレータ付きリスト（`','.expr+` / `sep.rule+`）、および Warth 左再帰を完全サポートし、CPython の `.gram` 構文および `tools/grammars/*.peg` をそのままコンパイル可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-25] Pure Python Packrat PEG Parser Engine Specification](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第3章 PEG/Packrat 構文解析フロントエンドのゼロコスト自動合成)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- 外部標準:
  - PEP 617: New PEG parser for CPython
  - CPython Grammar Specification (`Grammar/python.gram`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/core/peg/compiler/ast_nodes.py](../../src/core/peg/compiler/ast_nodes.py) (カット演算子 `~`、セパレータ付きリスト、角括弧オプショナル等の AST ノード追加)
- [ ] [src/core/peg/compiler/parser.py](../../src/core/peg/compiler/parser.py) (CPython PEG 構文：`rule:`, `name=expr`, `[e]`, `~`, `sep.rule+` 等のパース対応)
- [ ] [src/core/peg/compiler/codegen.py](../../src/core/peg/compiler/codegen.py) (CPython PEG 構文ノードの Python コード生成)
- [ ] [src/core/peg/runtime.py](../../src/core/peg/runtime.py) (カット演算子 `~` のバックトラック刈り取りランタイムサポート)
- [ ] [tests/core/test_peg_cpython_grammar.py](../../tests/core/test_peg_cpython_grammar.py) (新規: CPython PEG 構文コンパイル・実行検証テスト)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/907-support-cpython-peg-grammar-specification-in-core-peg`

1. **AST ノードの拡充 (`ast_nodes.py`)**:
   - `CutExpr`: カット演算子 `~`（マッチ成功後のバックトラックを無効化）
   - `GatherExpr`: セパレータ付きリスト（`sep.rule+` / `sep.rule*`）
   - 既存の `NamedExpr`, `ChoiceExpr`, `OptExpr` の柔軟な表現対応
2. **Meta-Grammar パーサーの拡張 (`parser.py`)**:
   - ルール定義構文: `rule: alt1 | alt2`（コロン `:` と矢印 `<-` の両対応）
   - 変数束縛構文: `name=expr`（イコール `=` とコロン `name:expr` の両対応）
   - オプショナル構文: `[expr]`（角括弧）および `expr?` の両対応
   - カット構文: `~` の認識
   - セパレータ記法: `sep.rule+` および `sep.rule*` の認識
3. **ランタイムおよびコードジェネレータの対応 (`runtime.py`, `codegen.py`)**:
   - `Cut` コンビネータおよびコンパイルコード出力の実装
   - `Gather`（セパレータ付きリスト）コンビネータの実装
4. **テストスイートの実装 (`tests/core/test_peg_cpython_grammar.py`)**:
   - CPython 記法による文法定義のパース、コード生成、および実行時構文解析の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/core/peg/compiler/parser.py` が CPython PEG 構文（`rule:`, `name=expr`, `[e]`, `~`, `sep.rule+`）をパースできること。
- [ ] `src/core/peg/compiler/codegen.py` が CPython PEG 構文から正しい Python パーサーコードを生成できること。
- [ ] 既存の Bryan Ford 記法（`<-`, `/`, `name:expr`）との後方互換性が 100% 維持されていること。
- [ ] `pytest tests/core/test_peg*.py` が 100% PASS すること。
- [ ] `make py_compile && make static_analysis` が PASS すること。
