---
ID: 767
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] LIR 分岐融合 (128)・ピープホール (133) の Picopass 化と基本ブロック内データ依存 DAG 走査の導入 (DSN-33-01 T5.3) (ID: 767)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 5.2 節（(2) LIR における命令データ依存 DAG 走査）、第 6.2 節、およびタスク **T5.3** に基づき、`ulisp/lir/128_lir_branch_fusion.scm` および `ulisp/lir/133_lir_peephole.scm` の手書き `cond` ループを **`define-picopass` ＋ `fuse-window-rules`** へ完全移行するとともに、基本ブロック内のレジスタ／スタックスロット（`%rsp + offset`）のデータ依存関係（RAW / WAW）を追跡する **LIR データ依存 DAG 走査** を導入する。

現在、`133_lir_peephole.scm` ではスタックへの `%store` 直後の `%load` を除去するために、2命令隣接用（Rule 2b）と3命令1ギャップ用（Rule 2b-2, Rule 2b-3）を別々に手書きしており、2命令以上離れると最適化できない。データ依存 DAG エッジ走査により、間に無関係な命令が何個挟まっていても単一の Picopass 規則で Store-Reload 転送・除去を行えるようにする。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 4.4 節, 第 5.2 節, 第 6.2 節, 第 6.3 節, 第 9.2 節 タスク **T5.3**)
- 依存関係:
  - 先行 Issue: [Issue #761 (T3.3: fuse-window-rules ドライバ実装)](761-implement-fuse-window-rules-for-lir-sliding-window.md), [Issue #766 (T5.2: Hash-Consing Term DAG と MIR Picopass 化)](766-implement-hash-consing-term-dag-and-memoized-catamorphism.md)
  - 後続 Issue: [Issue #768 (T6.1: define-pipeline 用途別編成)](768-implement-define-pipeline-for-aot-repl-and-check-modes.md), [Issue #769 (T6.2: Provenance 来歴追跡と Auto-Bisect)](769-implement-picopass-provenance-tracing-and-auto-bisect.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lir/128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)
- [ ] [ulisp/lir/133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/tests/passes/test_128_lir_branch_fusion.scm](../../ulisp/tests/passes/test_128_lir_branch_fusion.scm)
- [ ] [ulisp/tests/passes/test_133_lir_peephole.scm](../../ulisp/tests/passes/test_133_lir_peephole.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/767-lir-peephole-picopass-and-dependency-dag`

1. **`128_lir_branch_fusion.scm` の Picopass 化**:
   - `%cmp` / `%raw-cmp` + `%set-boolean` + `%jump-if-false` の融合規則群を `define-picopass`（`rule-lir-fuse-cmp-branch` 等）として定義し、`fuse-window-rules` で実行する。
2. **`133_lir_peephole.scm` の Picopass 化と基本ブロック内データ依存 DAG 追跡**:
   - 自己代入除去（`rule-lir-self-mov-elim`）、往復代入除去（`rule-lir-roundtrip-mov-elim`）、定数畳み込み、不要命令除去をそれぞれ独立した `define-picopass` として定義する。
   - 基本ブロック内のスタックスロット（`(%rsp + offset)`）とレジスタの最新定義（Reaching Definition / DAG Producer Edge）を追跡する `femtopass` / DAG ウィンドウヘルパーを導入し、Rule 2b / 2b-2 / 2b-3 を距離非依存の単一規則 `rule-lir-stack-store-load-forward` に統合する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `128_lir_branch_fusion.scm` と `133_lir_peephole.scm` の全規則が名前付き `define-picopass` として定義され、個別単体テストおよび個別 ON/OFF が可能であること。
- [ ] 間に2個以上の無関係な `%store` 命令が挟まった Store-Reload パターンもデータ依存追跡により転送・除去できること。
- [ ] `test_128_lir_branch_fusion.scm` および `test_133_lir_peephole.scm` が全件 PASS すること。

