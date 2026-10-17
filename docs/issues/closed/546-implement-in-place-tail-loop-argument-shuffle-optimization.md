---
ID: 546
種別: Feature
優先度: Medium
ステータス: Closed (Fixed)
完了日: 2026-10-17
---

# [FEAT/ENH] ULisp AOT x86における末尾ループ引数インプレース更新 (In-place Tail Loop Argument Shuffle) の最適化 (ID: 546)

## 1. 概要 / Summary
ULisp AOT x86 における自己末尾呼び出し（`(loop (+ i 1) (+ acc i))` 等）の生成コードにおいて、ループ次期引数を更新する際、複数の中間退避領域（`[rsp - 24]`, `[rsp - 32]` 等）を介在させてから元の引数レジスタに再ロードする冗長な引数シャッフルが発生していた。

本Issueでは、有向グラフによる並列代入（Parallel Copy）依存解析を導入し、以下の最適化を実装した：
1. **DAG依存最適化**:
   - `(+ acc i)` のように `acc` が更新前の `i` を参照し、`i` 側が `acc` を参照しない有向非巡回グラフ依存関係を検知。
   - 従属変数 `acc` を先にインプレース加算（`add r13, rbx`）してから独立変数 `i` をインプレース更新（`add rbx, 1`）。中間スタック退避スロットを完全排除。
2. **循環依存（Cycle）の最小スクラッチ解消**:
   - `(swap-loop b a)` のような変数入れ替え（スワップ）では、スクラッチレジスタ `%r10` を用いてサイクルを解消し、スタックアクセス 0回でレジスタ間代入（`mov r10, rbx; mov rbx, r13; mov r13, r10`）を実現。
3. **減算・単一変数同一性の最適化**:
   - カウントダウンループ `(- n 1)` に対するインプレース減算（`sub rbx, 1`）や、変化しない引数に対する無変更パススルーをサポート。

本最適化により、1,000,000回反復の純粋CPUループ処理時間が **0.985 ms から 0.379 ms**（約2.6倍高速化、ベースライン2.83ms比で約7.5倍高速化）へと飛躍的に向上した。

---

## 2. トレーサビリティ / Traceability
- 性能測定レポート: [outputs/benchmarks/all_lisp_benchmark_report.md](../../outputs/benchmarks/all_lisp_benchmark_report.md)
- 関連設計書: [docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md](../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- 関連Issue:
  - [closed/544-implement-loop-variable-register-allocation.md](544-implement-loop-variable-register-allocation.md) (ループ変数レジスタ割付)
  - [closed/545-implement-condition-branch-flag-fusion.md](545-implement-condition-branch-flag-fusion.md) (条件分岐融合)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (`lir-compile-in-place-cont-call`, `lir-compile-let`, `lir-compile-cont-call`)
- [ulisp/tests/passes/test_inplace_shuffle.scm](../../ulisp/tests/passes/test_inplace_shuffle.scm) (新規テストスイート: 9/9 PASS)
- [ulisp/tests/passes/test_loop_register_allocation.scm](../../ulisp/tests/passes/test_loop_register_allocation.scm) (レジスタ利用アサーション適合)
- [ulisp/Makefile](../../ulisp/Makefile) (`test_inplace_shuffle` ターゲット追加)

---

## 4. 実装内容 / Implementation Details

### 4.1. LIR インプレース末尾引数シャッフル
`ulisp/passes/06_lir.scm` に `lir-compile-in-place-cont-call` を導入し、ANF が生成する `(let ((t0 e0) (t1 e1) ...) (%cont-call loop t0 t1 ...))` パターンおよび直接 `%cont-call` を捕捉：
- `expr-references-var?` により引数間の依存関係を有向解析。
- 干渉のない順序で先行評価・直接レジスタ代入または直接算術（`%add`, `%sub`）を出力。
- 相互依存（サイクル）時は `%r10` 一時レジスタで解決。

### 4.2. 生成アセンブリ比較 (loop_sum 1,000,000回)
**最適化前**:
```assembly
.L_else_2:
    mov rax, rbx
    mov [rsp - 24], rax
    mov rax, 1
    add rax, [rsp - 24]
    mov [rsp - 24], rax
    mov rax, rbx
    mov [rsp - 32], rax
    mov rax, r13
    add rax, [rsp - 32]
    mov [rsp - 32], rax
    mov rax, [rsp - 24]
    mov r10, rax
    mov rax, [rsp - 32]
    mov rbx, r10
    mov r13, rax
    jmp .L_cont_entry__0
```

**最適化後**:
```assembly
.L_else_2:
    add r13, rbx
    add rbx, 1
    jmp .L_cont_entry__0
```
メモリ転送命令およびスタック退避・復元を完全に 0 回に圧縮。

---

## 5. 完了条件の検証結果 / Definition of Done (DoD) Verification
- [x] **スタック退避完全排除**: タイトループ内での中間スタック退避スロット（`[rsp - 24]`, `[rsp - 32]` 等）へのストア・ロードが 0 回であることを自動検証。
- [x] **循環依存対応**: 変数入れ替えループ `(swap-loop b a)` において、スクラッチレジスタ `%r10` によるサイクル解消と正常値算出（10）を検証。
- [x] **テスト完全通過**:
  - `make -C ulisp test_inplace_shuffle`: 9/9 PASS
  - `make -C ulisp test_loop_reg`: 8/8 PASS
  - `make -C ulisp test_branch_fusion`: 7/7 PASS
  - 100万回反復純粋CPU実行時間: 0.379 ms
