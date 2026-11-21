---
ID: 931
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] PEG による C99 文法仕様 (`tools/grammars/c99.peg`) の定義およびパーサー自動合成の実装 (ID: 931)

## 1. 概要 / Summary
[[DSN-25]](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md) および [[DSN-33-22]](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) §3（PEG / Packrat 構文解析フロントエンドのゼロコスト自動合成 / Issue #894, #907, #908）に基づき、C99 言語の完全な構文規則を CPython PEG 構文（PEP 617 準拠）で記述した宣言的文法ファイル `tools/grammars/c99.peg` を新設し、Pure Scheme Packrat PEG パーサージェネレータおよび `src/core/peg/` の双方から C99 構文解析器を自動合成可能にする。

これにより、[[Issue #915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md) の C99 パーサー実装における手書きのボイラープレートを排除し、C 言語特有の左再帰演算子・`typedef` 文脈曖昧性（Lexer Hack）・宣言子構文を宣言的な PEG 規則と順序付き選択（Ordered Choice `|`）＋セマンティック述語として厳密に定義・保守できるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-11 §4.2 (C99 構文解析・型検査)](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-22 §3 (PEG 構文解析フロントエンド自動合成)](../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [DSN-33-32 §2.2, §6.1 (Lua C コンパイルロードマップ)](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-25 (Pure Python Packrat PEG Parser Engine)](../designs/DSN-25-pure_python_packrat_peg_parser_engine.md)
- 前提基盤 Issue: #894 (Pure Scheme PEG ジェネレータ), #907 (PEP 617 仕様対応), #908 (`tools/grammars/*.peg` 統一), #837 (Binding ID), #824 (Source Span)
- 連携 Issue: [[Issue #915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md) (C99 パーサーおよび Nanopass C-AST 構築)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `tools/grammars/c99.peg` (新規: CPython PEG / PEP 617 準拠の C99 完全文法定義)
- [ ] `ulisp/frontend_c/parser.scm` (`c99.peg` から生成または駆動される C99 構文解析フロントエンド)
- [ ] `ulisp/peg/` (`ulisp/workbench/peg` 連携: トークンストリーム入力・左再帰メモ化・セマンティック述語サポート強化)
- [ ] `ulisp/tests/test_c99_peg_grammar.scm` (新規: C99 PEG 文法単体・Lua ヘッダ/ソースパース検証)
- [ ] `tests/core/peg/compiler/test_c99_grammar.py` (新規: `src/core/peg/` 側での `c99.peg` コンパイル整合性検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/931-implement-c99-peg-grammar`

1. **`tools/grammars/c99.peg` の作成（CPython PEG / PEP 617 記法準拠）**:
   - ISO/IEC 9899:1999 (C99) 文法（外部定義、宣言、指定子・修飾子、`struct`/`union`/`enum`、宣言子・抽象宣言子、初期化子・指示付き初期化子、文、`switch`/`case`/`goto`、式）をすべて `rule: choice1 | choice2`、`name=expr`、`[expr]`、`sep.rule+` 形式で記述する。
2. **Packrat 左再帰メモ化による演算子・後置式の表現**:
   - C99 の二項式（乗除算・加減算・シフト・関係・ビット・論理・代入・カンマ）、後置式（`[]`, `()`, `.`, `->`, `++`, `--`）、および `direct_declarator` の左再帰規則を、Warth らの左再帰シード成長アルゴリズム（Packrat 左再帰対応）で無限再帰なし・$O(N)$ 線形時間で解析可能にする。
3. **`binding.scm` (#837) 連動セマンティック述語による Lexer Hack 解消**:
   - `typedef_name: &is_typedef_name IDENTIFIER` のような PEG 先読みセマンティック述語（`&predicate` / `!predicate`）を導入し、文脈に応じて `TYPEDEF_NAME` と通常識別子・構造体宣言・キャスト `(type)expr` vs 括弧式 `(expr)` を順序付き選択（`|`）で曖昧さなく分岐させる。
4. **Nanopass `L_c_ast` 直接合成**:
   - セマンティックアクションにて直接 `<source-span>`（#824）および `<binding-id>`（#837）を保持した `L_c_ast` S式ノードを生成し、`ulisp/frontend_c/sema.scm`（#916）へ引き渡す。
5. **Lua 5.x ソース群（約3万行）に対するパース網羅テスト**:
   - プリプロセス済みの Lua 5.x 全 C ソースファイルが `c99.peg` ベースのパーサーで構文エラー 0 件でパースできることを検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `tools/grammars/c99.peg` が `src/core/peg/` および `ulisp/peg/`（Pure Scheme PEG コンパイラ）の両方で正常にコンパイル・パーサー生成できること。
- [ ] C99 の左再帰式、複雑な関数ポインタ宣言子、`typedef` シャドウイング、`sizeof(type)` vs `sizeof expr`、指示付き初期化子が正しくパースされ `L_c_ast` が構築されること。
- [ ] プリプロセス済みの Lua 5.x 全 C ファイルが本 PEG 文法パーサーでエラー 0 件で構文解析できること。
- [ ] `ulisp/tests/test_c99_peg_grammar.scm` および `tests/core/peg/compiler/test_c99_grammar.py` が全件 PASS すること。
