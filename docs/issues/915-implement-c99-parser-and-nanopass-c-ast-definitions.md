---
ID: 915
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 構文解析器 (Parser) および Nanopass C-AST 言語定義・Lexer Hack 解消の実装 (ID: 915)

## 1. 概要 / Summary
プリプロセス済みの C99 トークンストリームを構文解析し、Nanopass 言語定義に基づく型準備 C AST（`L_c_ast`）を構築する構文解析器（`ulisp/frontend_c/parser.scm` および `ulisp/frontend_c/c_lang.scm`）を実装する（Step S2 / T3）。Issue #837（Binding ID・統一スコープ管理）と協調して C 言語特有の `typedef` 曖昧性（Lexer Hack）をクリーンに解消する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §2, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §3.2, §4.2](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
- 前提基盤 Issue: #837 (Binding ID), #824 (Source Span), #914 (CPP)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/c_lang.scm` (新規: Nanopass `L_c_ast` / `L_c_typed` 言語スキーマ定義)
- [ ] `ulisp/frontend_c/parser.scm` (新規: 再帰下降 + 演算子順位 C99 パーサ)
- [ ] `ulisp/tests/test_c99_parser.scm` (新規: 構文解析 ＆ `typedef` スコープテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/915-implement-c99-parser-and-c-ast`

1. `define-language L_c_ast` により翻訳単位、宣言、型指定子（基本型・`struct`/`union`/`enum`・`typedef`・修飾子 `const`/`volatile`/`static`/`extern`/`inline`）、宣言子（ポインタ・配列・関数ポインタ）、文（`if`/`while`/`for`/`do-while`/`switch`/`case`/`goto`/ラベル）、式ノードを定義する。
2. [binding.scm](../../ulisp/compiler/binding.scm) を活用し、通常識別子・タグ・`typedef`・ラベルの名前空間とブロックスコープのシャドウイングを管理し、`TYPEDEF_NAME` と `IDENTIFIER` を正確に識別する。
3. C99 の宣言子・抽象宣言子（`int (*(*fp)(int))[4]` や `sizeof(type)` キャスト区別）および演算子優先順位・結合性を完全サポートする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `L_c_ast` が Nanopass 検証を通り、全ノードに `<source-span>` と `<binding-id>` が保持されること。
- [ ] `typedef` と同名ローカル変数によるシャドウイング（Lexer Hack ケース）がエラーなくパースできること。
- [ ] `ulisp/tests/test_c99_parser.scm` が全件 PASS すること。
