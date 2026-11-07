---
ID: 754
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] nanopass-catamorphism-step の HIR 8構文ハードコード撤去と define-language スキーマ駆動再帰走査化 (DSN-33-01 T1.2) (ID: 754)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.2 節（課題①・課題③）およびタスク **T1.2** に基づき、`ulisp/compiler/nanopass_meta.scm` 内の自動再帰走査エンジン `nanopass-catamorphism-step` および文法照合器 `nanopass-production-matches?` から特定言語（HIR / `L_lifted`）のハードコードと暗黙の構文書き換え副作用を完全撤去し、`define-language` の生成規則メタデータに基づく真の**スキーマ駆動カタモルフィズム**へ刷新する。

現在、`nanopass_meta.scm` には以下の3つの深刻な設計上の歪みが存在する：
1. **HIR 8構文のハードコード**: `nanopass-catamorphism-step`（L948-990）が `lang-in` の `define-language` 定義を参照せず、`quote`, `if`, `begin`, `lambda`, `let`, `letrec`, `set!`, `%program` の8構文だけを `case op` でハードコードしている。そのため LIR（`%block`, `%function`）や Backend（`%asm-program`, `%asm-function`）で `define-pass` を使用すると、命令タグ自体に対して誤って再帰走査が呼ばれてしまう。
2. **カタモルフィズム内の暗黙の脱糖副作用**: `nanopass-catamorphism-step` の `lambda`, `let`, `letrec` 分岐（L958-980）において、複数式のボディを勝手に `(begin ...)` で包む書き換えが混入しており、`028_desugar_bindings.scm` / `030_desugar.scm` の明示的ルールと責務が重複している。
3. **汎用文法チェッカへの `L_lifted` ハードコード混入**: `nanopass-production-matches?`（L379-389）に `(if (eq? (nanopass-lang-name lang) 'L_lifted) ...)` が直接ハードコードされている。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 8.2 節 課題①・課題③, 第 8.4 節, 第 9.2 節 タスク **T1.2**)
- 依存関係:
  - 先行 Issue: [Issue #753 (T1.1: 言語定義ファイルの統廃合と extends 連鎖の確立)](753-consolidate-define-language-files-and-establish-extends-chain.md)
  - 後続 Issue: [Issue #755 (T1.3: 未変更部分木の構造共有と重複 Trace 整理)](755-implement-catamorphism-structural-sharing-and-unify-trace-hooks.md), [Issue #764 (T4.3: Verifier の attopass 化)](764-migrate-verifier-to-attopass-and-eliminate-triple-traversal.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/754-schema-driven-catamorphism`

1. **`define-language` スキーマ駆動の再帰位置判定エンジンの実装**:
   - `nanopass_meta.scm` に、指定された言語 `lang-in` と非終端記号 `nt-name` の生成規則（productions）を参照して、与えられた式 `ir` の各サブフォームが「終端記号（再帰不要: `quote` のデータ、束縛変数名リスト、ラベル名、レジスタ名等）」か「非終端記号（再帰対象: `Expr`, `Inst`, `FunctionDecl` 等）」かを判定し、非終端記号の位置のみに `call-recurse`（または対応する非終端記号トランスフォーマ）を適用する `nanopass-schema-catamorphism-step` を実装する。
   - 言語指定が未登録またはワイルドカード `*` の場合のフォールバックとしてのみ従来の S 式汎用再帰を維持する。
2. **暗黙の複数式ボディ `(begin ...)` 正規化の分離**:
   - `028_desugar_bindings.scm` および `030_desugar.scm` で `lambda`, `let`, `letrec` の複数式ボディ正規化ルールがすべてのケース（名前付き `let` や空ボディ含む）を網羅していることを確認した上で、`nanopass-catamorphism-step` 内の暗黙の `(begin ...)` 変換副作用を除去し、純粋な構造保存再帰にする。
3. **`nanopass-production-matches?` からの `L_lifted` 分岐の分離**:
   - `nanopass-production-matches?`（L379-389）内の `has-unlifted-lambda?` チェックは、`L_lifted` の `Expr` から `(- (lambda (x ...) e ...))` が除去されていることによりスキーマ検証自体で自然に検出されるよう、`L_lifted` の `FunctionDecl` の内部式 `e` が `Expr` として再帰検証されるように修正し、特定言語名 `'L_lifted` のハードコード分岐を削除する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `nanopass-catamorphism-step` が `L_src` / `L_core` だけでなく、`L_anf`, `L_lifted`, `L_lir_canonical`, `L_asm_x86` の構文（`%function`, `%block`, `%asm-program` 等）に対しても、`define-language` のスキーマ定義に従って正確に子ノードを再帰走査できること。
- [ ] `nanopass-production-matches?` 内に特定言語名（`'L_lifted`）のハードコード分岐が存在しないこと。
- [ ] `ulisp/tests/test_nanopass_framework.scm` に LIR / Backend 言語定義を用いた自動カタモルフィズム走査テストを追加し、全件 PASS すること。

