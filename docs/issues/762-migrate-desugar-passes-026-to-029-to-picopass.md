---
ID: 762
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] フロントエンド脱糖パス (026〜029) の全規則 define-picopass 化と 1行S式ユニットテストの整備 (DSN-33-01 T4.1) (ID: 762)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 6.2 節、第 9.2 節 タスク **T4.1** に基づき、フロントエンド脱糖サブモジュール群（`026_desugar_constructors.scm`, `027_desugar_conditionals.scm`, `028_desugar_bindings.scm`, `029_desugar_dynamic.scm`）の各構文変換規則を第一級オブジェクトである **`define-picopass`** として再定義し、単体テストパス（`desugar-constructors`, `desugar-conditionals`, `desugar-bindings`, `desugar-dynamic`）もそれらの Picopass を `(fuse-rules ...)` で束ねた Nanopass として再構築する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 1.1 節, 第 6.2 節, 第 7.1 節, 第 9.2 節 タスク **T4.1**)
- 依存関係:
  - 先行 Issue: [Issue #758 (T2.3: Pass 015 への新 DSL 統合)](758-integrate-picopass-dsl-into-pass-015-expander.md), [Issue #760 (T3.2: 5ステップ融合サイクルと局所再適用)](760-implement-local-redispatch-and-extends-eliminates-validation.md)
  - 後続 Issue: [Issue #763 (T4.2: 030_desugar.scm の重複190行撤去と fuse-rules 完全置換)](763-replace-desugar-030-duplicate-rules-with-fuse-rules.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [ ] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm)
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/029_desugar_dynamic.scm](../../ulisp/frontend/029_desugar_dynamic.scm)
- [ ] [ulisp/tests/passes/test_026_desugar_constructors.scm](../../ulisp/tests/passes/test_026_desugar_constructors.scm)
- [ ] [ulisp/tests/passes/test_027_desugar_conditionals.scm](../../ulisp/tests/passes/test_027_desugar_conditionals.scm)
- [ ] [ulisp/tests/passes/test_028_desugar_bindings.scm](../../ulisp/tests/passes/test_028_desugar_bindings.scm)
- [ ] [ulisp/tests/passes/test_029_desugar_dynamic.scm](../../ulisp/tests/passes/test_029_desugar_dynamic.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/762-migrate-desugar-026-029-to-picopass`

1. **Pass 026（Constructors: `026_desugar_constructors.scm`）の Picopass 化**:
   - `rule-desugar-list`, `rule-desugar-vector`, `rule-desugar-bytevector`, `rule-desugar-string-ops`, `rule-desugar-vector-ops`, `rule-desugar-bytevector-ops`, `rule-desugar-math-variadic` (`gcd`, `lcm`, `max`, `min`), `rule-desugar-format`, `rule-desugar-cxr` (`caar`〜`cadddr`) を `define-picopass` として定義し、`desugar-constructors` を `(fuse-rules ...)` で構成する。
2. **Pass 027（Conditionals: `027_desugar_conditionals.scm`）の Picopass 化**:
   - `rule-desugar-cond-expand`, `rule-desugar-cond`, `rule-desugar-case`, `rule-desugar-and`, `rule-desugar-or`, `rule-desugar-chain-cmp`（`char<?`〜`string-ci=?`）を `define-picopass` として定義し、`desugar-conditionals` を `(fuse-rules ...)` で構成する。
3. **Pass 028（Bindings: `028_desugar_bindings.scm`）の Picopass 化**:
   - `rule-desugar-case-lambda`, `rule-desugar-let*`, `rule-desugar-letrec*`, `rule-desugar-named-let`, `rule-desugar-multi-body` (`let`/`letrec`/`lambda`), `rule-desugar-do`, `rule-desugar-internal-define` を `define-picopass` として定義し、`desugar-bindings` を `(fuse-rules ...)` で構成する。
4. **Pass 029（Dynamic & Multiple Values: `029_desugar_dynamic.scm`）の Picopass 化**:
   - `rule-desugar-guard`, `rule-desugar-let-values`, `rule-desugar-define-values`, `rule-desugar-parameterize`, `rule-desugar-delay`, `rule-desugar-values`, `rule-desugar-error-assume`, `atto-no-unexpanded-let-syntax` を定義し、`desugar-dynamic` を `(fuse-rules ...)` で構成する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `026`〜`029` のすべての変換規則が名前付き `define-picopass`（および `define-attopass`）として定義されていること。
- [ ] `test_026`, `test_027`, `test_028`, `test_029` に加え、個別 Picopass を直接呼び出す 1 行 S 式ユニットテストが全件 PASS すること。

