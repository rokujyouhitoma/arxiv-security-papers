---
ID: 761
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] LIR 命令列向け fuse-window-rules スライディングウィンドウ走査および収束ドライバの実装 (DSN-33-01 T3.3) (ID: 761)

## 1. 概要 / Summary

[[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) の第 4.4 節、第 6.3 節（3. LIR スライディングウィンドウ）、およびタスク **T3.3** に基づき、基本ブロック内の線形命令列 `(inst_1 inst_2 inst_3 . rest)` に対して複数の命令融合・ピープホール Picopass をスライディングウィンドウ方式で適用する走査ドライバ **`fuse-window-rules`** を実装する。

現在、LIR 分岐融合（`128_lir_branch_fusion.scm`）、LIR ピープホール（`133_lir_peephole.scm`）、および x86 ピープホール（`143_backend_x86_peephole.scm`）は、それぞれ独自の手書き `let loop ((rest insts) (acc '()))` と深い `car`/`cadr`/`caddr` ネストによって実装されている。`fuse-window-rules` により、これらを宣言的な `define-picopass` ルール群として記述・融合可能にする。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md) (第 2.3 節, 第 4.4 節, 第 6.3 節, 第 9.2 節 タスク **T3.3**)
- 依存関係:
  - 先行 Issue: [Issue #760 (T3.2: 5ステップ融合サイクルと局所再適用)](760-implement-local-redispatch-and-extends-eliminates-validation.md)
  - 後続 Issue: [Issue #767 (T5.3: 128/133 LIR ピープホールの Picopass 化とデータ依存 DAG)](767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/tests/test_nanopass_framework.scm](../../ulisp/tests/test_nanopass_framework.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/761-implement-fuse-window-rules`

1. **命令窓（`InstWindow`）パターンマッチングとスライディング走査器の実装（`nanopass_meta.scm`）**:
   - 命令リスト `insts` の先頭から `((inst1 inst2 . ,rest) => <new-prefix-or-rest>)` 形式の Picopass 群を試行し、いずれかの規則がマッチした場合は置換後の命令リストに対して再試行し、どの規則もマッチしない場合は `(car insts)` を確定させて `(cdr insts)` へ窓を1つ進める `nanopass-run-window-rules` を実装する。
   - `%lir-program`（関数リスト＋メイン命令列）または単一の命令リストの双方を受け付け、関数ボディおよびメインボディの命令列に対して自動的にウィンドウ走査を適用するラッパーを提供する。
   - 複数回のパスで新たに隣接した命令同士（例: 間の不要 `%mov` が消えたことで隣り合った `%store` と `%load`）も確実に最適化されるよう、オプションで不動点収束ループ（`fixpoint`）をサポートする。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `define-picopass` で定義した1命令削除ルール（例: `((%mov ,r ,r) . ,rest) -> rest`）や2〜3命令融合ルールを `(fuse-window-rules ...)` で束ねた `define-pass` が、命令列および `%lir-program` に対して正しく動作すること。
- [ ] 先頭命令のオペコード（`%mov`, `%store`, `%cmp` 等）に基づく高速ディスパッチが行われること。
- [ ] `ulisp/tests/test_nanopass_framework.scm` にて `fuse-window-rules` の単体テストが全件 PASS すること。

