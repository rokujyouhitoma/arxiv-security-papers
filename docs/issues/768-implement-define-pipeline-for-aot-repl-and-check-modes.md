---
ID: 768
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] define-pipeline による用途別パイプライン (AOT / REPL / Check-only) の宣言的編成と動的切り替え (DSN-33-01 T6.1) (ID: 768)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 2.1 節〜第 2.3 節（最上位：Pipeline 層）、第 5.1 節、およびタスク **T6.1** に基づき、`ulisp/compiler/pass_manager.scm` に最上位の配線・実行計画 DSL である **`define-pipeline`** を実装し、共通の Pass / Nanopass 部品群から用途に応じた複数のパイプライン（AOT ネイティブ生成用、対話型 REPL / 高速 `eval` 用、静的検査・LSP 専用）を宣言的に定義・切り替えられるようにする。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 2.1 節〜第 2.3 節, 第 5.1 節, 第 9.2 節 タスク **T6.1**)
- 依存関係:
  - 先行 Issue: [Issue #765 (T5.1: ルール依存 DAG 自動構築)](765-implement-rule-dependency-dag-and-femtopass-cache-invalidation.md), [Issue #767 (T5.3: LIR ピープホールの Picopass 化)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
  - 後続 Issue: [Issue #769 (T6.2: Provenance 来歴追跡と Auto-Bisect)](769-implement-picopass-provenance-tracing-and-auto-bisect.md), [Issue #770 (T6.3: 3-Stage セルフホスティング不動点検証)](770-verify-stage3-self-hosting-fixed-point-and-benchmark-pass-fusion.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/frontend/015_dsl_expander.scm](../../ulisp/frontend/015_dsl_expander.scm)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm)
- [ ] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/768-implement-define-pipeline`

1. **`define-pipeline` DSL とパイプラインレジストリの実装**:
   - `pass_manager.scm` に `*pipeline-registry*`（`register-pipeline!`, `lookup-pipeline`, `select-pipeline!`）を追加し、`define-pipeline` マクロ（および `015_dsl_expander.scm` の展開サポート）を実装する。
2. **3つの標準パイプラインプロファイルの定義**:
   - `aot-native-pipeline`: Frontend $\to$ MIR 最適化 $\to$ LIR 生成・ピープホール $\to$ Target Backend のフルパイプライン。
   - `repl-fast-pipeline`: Frontend（マクロ展開・Core 脱糖・スコープ解決）のみを通し、重い MIR/LIR 最適化パスをスキップして即座に評価または最小コード生成へ渡す超低レイテンシパイプライン。
   - `static-check-pipeline`: Frontend ＋ スコープ・アリティ・型推論・アフィン所有権 Attopass のみを実行し、LIR・機械語生成を行わない高速検証パイプライン。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `define-pipeline` により複数の名前付きパイプラインを定義でき、`select-pipeline!` または `run-named-pipeline` で切り替えて実行できること。
- [ ] 各パイプライン定義時に `validate-pipeline-prerequisites` および入出力言語スキーマ（$L_{\text{out}} = L_{\text{in\_next}}$）の連続性が自動検証されること。
- [ ] `test_pass_manager.scm` にて用途別パイプラインの実行・切り替えテストが全件 PASS すること。

