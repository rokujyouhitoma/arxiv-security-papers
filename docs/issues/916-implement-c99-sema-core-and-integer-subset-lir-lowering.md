---
ID: 916
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 基本型検査・整数昇格 (Sema Core) および整数サブセット Core LIR Lowering の実装 (ID: 916)

## 1. 概要 / Summary
C99 AST に対して基本型検査・暗黙の整数昇格（Integer Promotion）・通常の算術変換を施して `L_c_typed` を生成する意味解析器（`ulisp/frontend_c/sema.scm`）と、整数演算・制御構造・文字列リテラル・`printf` 等の外部 `'sysv` 呼び出しを `DSN-33-13` Core Machine LIR へ降格する Lowering エンジン（`ulisp/frontend_c/lower_to_lir.scm`）を実装する（Step S2 / T4）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §4.2, §4.3](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §2.1, §3.2, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #826 (Typed LIR), #827 (Braun SSA), #828 (符号なし演算), #835 (Core LIR 分離), #915 (Parser)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/sema.scm` (新規: 基本型検査・暗黙型変換挿入・`L_c_typed` 生成)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (新規: `L_c_typed` $\to$ Core Machine LIR 降格)
- [ ] `ulisp/tests/test_c99_int_lowering.scm` (新規: Reference VM #834 および C/x86 実行検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/916-implement-c99-sema-core-and-int-lowering`

1. `sema.scm`: `char`/`short`/`int`/`long`/`long long` の符号付き・符号なし整数型、暗黙の整数昇格（`i8`/`i16` $\to$ `i32`）、通常の算術変換（`%sext`/`%zext`/`%trunc`）、短絡評価論理演算（`&&`, `||`）、および `L_c_typed` における型エラーの Pretty Diagnostic（#833）報告を実装する。
2. `lower_to_lir.scm`: Managed Runtime Dialect を完全にバイパスし、ローカル変数を `%alloca` として Core Machine LIR を出力して Pass 132 Braun SSA でレジスタ昇格させる。文字列リテラルを `.rodata` セクションへ配置し、外部関数呼び出しに `calling-convention: 'sysv` を付与する。
3. Reference VM（[lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)）を用いて整数制御フロー・再帰・ループの動作を先行検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `lower_to_lir.scm` が Managed Dialect 命令を一切出力せず、純粋な Core Machine LIR のみを生成すること。
- [ ] 整数演算・符号付き/符号なし比較・短絡評価・ループ・再帰呼び出しが Reference VM 上で正しく動作すること。
- [ ] 不正な型代入・未宣言識別子に対して `diagnostic.scm` による Span 付きエラーが出力されること。
