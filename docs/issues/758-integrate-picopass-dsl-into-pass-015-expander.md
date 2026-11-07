---
ID: 758
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Pass 015 (015_dsl_expander.scm) 先行 DSL 展開器への pico / femto / atto 構文統合 (DSN-33-01 T2.3) (ID: 758)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 8.1 節（領域⑥）およびタスク **T2.3** に基づき、ULisp コンパイラ自身のセルフホスティング AOT ビルド時に Nanopass DSL 構文を先行展開する Pass 015（`ulisp/frontend/015_dsl_expander.scm`）を拡張し、`define-picopass`, `define-femtopass`, `define-attopass`（および将来追加される `define-pipeline`）を正準 Scheme 定義へと展開できるようにする。

ULisp はインタプリタ（ILisp）実行時は `nanopass.scm` 内の `define-macro` を用いる一方、AOT コンパイラパイプライン（`run-pass-pipeline`）および 3-Stage セルフホスティングでは Pass 015 の手続き型展開器 `expand-dsl-forms` が DSL フォームを展開する。そのため、両者が 1 対 1 で完全同期していなければセルフホスティングが成立しない。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 8.1 節, 第 9.2 節 タスク **T2.3**)
- 依存関係:
  - 先行 Issue: [Issue #756 (T2.1: Rule Descriptor と Picopass DSL 実装)](756-implement-rule-descriptor-and-picopass-femtopass-attopass-dsl.md), [Issue #757 (T2.2: 関数合成コンビネータ群の実装)](757-implement-picopass-strategy-combinators.md)
  - 後続 Issue: [Issue #759 (T3.1: fuse-rules と O(1) ディスパッチ)](759-implement-fuse-rules-and-head-tag-o1-dispatch.md), [Issue #762 (T4.1: 026〜029 の Picopass 化)](762-migrate-desugar-passes-026-to-029-to-picopass.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/tests/passes/test_015_dsl_expander.scm](../../ulisp/tests/passes/test_015_dsl_expander.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/758-integrate-picopass-into-pass-015`

1. **`015_dsl_expander.scm` の `expand-dsl-forms` 拡張**:
   - `%source-loc` ラッパー内のフォーム判定リスト（L23）に `define-picopass`, `define-femtopass`, `define-attopass` を追加し、ソース位置情報（ファイル・行・列）を展開後の定義群へ正確に伝播させる。
   - トップレベル分岐に `nanopass-expand-define-picopass`, `nanopass-expand-define-femtopass`, `nanopass-expand-define-attopass` の呼び出しを追加し、`begin` ブロックの場合はフラットに展開リストへ連結する。
2. **コンパイル時ルール登録の保証**:
   - AOT コンパイル中に先行定義された `define-picopass` が、同じコンパイル単位の直後に現れる `define-pass` の `(fuse-rules ...)` で即座に参照できるよう、`nanopass-expand-define-picopass` 等の展開時にコンパイル時ルールレジストリへの登録も同時に行われるようにする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `expand-dsl-forms` が `%source-loc` 付き・無しの双方で `define-picopass`, `define-femtopass`, `define-attopass` を正準 `define` 群へ展開できること。
- [ ] 同一ソースファイル内で `define-picopass` の直後に記述された `define-pass` が、Pass 015 展開時にその Picopass 記述子を参照できること。
- [ ] `ulisp/tests/passes/test_015_dsl_expander.scm` に新構文の展開テストを追加し、全件 PASS すること。

