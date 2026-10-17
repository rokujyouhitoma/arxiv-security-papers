---
ID: 544
種別: Feature
優先度: High
ステータス: Closed
解決日: 2026-10-17
---

# [FEAT/ENH] ULisp AOT x86における末尾再帰ループ変数の汎用レジスタピン留め割付 (ID: 544)

## 1. 概要 / Summary
最新の多系統Lisp/Scheme性能測定（[outputs/benchmarks/all_lisp_benchmark_report.md](../../../outputs/benchmarks/all_lisp_benchmark_report.md)）において、ULisp AOT x86は再帰・クロージャで全処理系中最速を記録したものの、単純な反復ループ積算（`loop_sum` 100万回）において **2.62 ms** を要し、GCC -O2 最適化を適用した ULisp AOT C バックエンド（**0.54 ms**）に対して約4.8倍のレイテンシ差が生じていた。

機械語解析の結果、`ulisp/passes/06_lir.scm` の `lir-compile-variable` がすべてのローカル変数をスタックオフセット（`[rsp - X]`）として管理しており、ループ引数が毎反復でスタックに15回以上ロード/ストア（スピル）されていることが判明した。

本Issueでは、末尾再帰（`letrec` / named `let` / contified `%cont-fun`）のループ引数を x86-64 の callee-saved 汎用レジスタ（`%rbx`, `%r13`, `%r14`）にピン留め割り当て（Register Allocation）する最適化パスを導入し、ループ反復中のメモリアクセスを完全排除した。

---

## 2. トレーサビリティ / Traceability
- 性能測定レポート: [outputs/benchmarks/all_lisp_benchmark_report.md](../../../outputs/benchmarks/all_lisp_benchmark_report.md)
- 関連設計書: [docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md](../../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- 関連Issue: #515 (性能評価基盤), #504 (Portable Cバックエンド), #502 (LIR分離), #545 (条件分岐融合), #546 (末尾引数シャッフル)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](../../../ulisp/passes/06_lir.scm) (LIR環境における `(reg . %reg)` 束縛表現の追加、自己末尾呼び出しループ引数のレジスタ昇格解析、`lir-compile-cont-fun` でのレジスタ退避/復元)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../../ulisp/passes/07_backend_x86_64.scm) (`reg->str` / `operand->str` / `x86-param-location` での `%rbx`, `%r13`, `%r14` サポート、`%push` / `%pop` 命令エミッタ)
- [x] [ulisp/passes/07_backend_c.scm](../../../ulisp/passes/07_backend_c.scm) (Cバックエンドの `reg_rbx`, `reg_r13`, `reg_r14` 同期サポート)
- [x] [ulisp/tests/passes/test_loop_register_allocation.scm](../../../ulisp/tests/passes/test_loop_register_allocation.scm) (レジスタ割り当て、%block / %jump レジスタ引数、アセンブリ検証、実行整合性テスト)
- [x] [tools/bench_scheme_entry.c](../../../tools/bench_scheme_entry.c) (Scheme関数直接呼び出しによるナノ秒単位純粋CPUレイテンシ測定ベンチマークハーネス)

---

## 4. 実装成果と測定結果 / Implementation & Verification Results

### 1. ループ本体のアセンブリ比較
- **最適化前 (Stack Spilling)**:
  毎反復で `[rsp - 24]`, `[rsp - 32]` へのメモリストアおよび `mov rax, [rsp - X]` が頻発。
- **最適化後 (Register Pinned)**:
  ```assembly
  .L_block_loop_cont_entry_0:
      push rbx
      push r13
      push r14
  .L_block_loop_1:
      ; rbx = n, r13 = acc
      cmp rbx, 0
      je .L_exit
      add r13, rbx
      sub rbx, 1
      jmp .L_block_loop_1
  .L_exit:
      mov rax, r13
      pop r14
      pop r13
      pop rbx
  ```
  ループ反復内のメモリアクセスが **0回** に削減。

### 2. 純粋CPU実行レイテンシ（1,000,000回反復積算 `loop_sum`）
- **最適化前**: **2.834 ms**
- **最適化後**: **1.442 ms**
- **改善率**: **49.1% 短縮（1.96倍 高速化）**
- **計算結果**: `499999500000`（完全一致・整合性検証完了）

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `loop_sum` の生成アセンブリにおいて、ループ本体内の `mov rax, [rsp - X]` が排除され、レジスタ間命令に変換されていること。
- [x] `make -C ulisp test_loop_reg` の全テスト（8項目）が 100% PASS すること。
- [x] `loop_sum` の実行時間が大幅に短縮（2.83ms -> 1.44ms, 1.96倍高速化）され、計算結果 `499999500000` の整合性が保たれていること。
