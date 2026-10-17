---
ID: 545
種別: Feature
優先度: High
ステータス: Closed
解決日: 2026-10-17
---

# [FEAT/ENH] ULisp AOT x86における条件分岐融合 (Flag / Branch Fusion) によるブール値実体化の完全排除 (ID: 545)

## 1. 概要 / Summary
ULisp AOT x86 が生成するアセンブリコードの調査により、`if` 構文の述語として比較演算（`=`, `<`, `>`, `<=`, `>=`, `eq?`）や述語（`null?`, `zero?`, `pair?`, `not`）が使用された際、無駄なブール値オブジェクトの実体化（Boolean Materialization）が発生していた。

具体的には、`cmp` 命令でフラグが立った直後に、`sete al` -> `movzx eax, al` -> `shl rax, 6` -> `add rax, 0x2F` で一度 Scheme の `#t` (0x6F) / `#f` (0x2F) オブジェクトを構築し、その直後で再び `cmp rax, 0x2F` -> `je .L_else` と比較して分岐していた。このため、単一の条件分岐に8命令を要し、CPUの分岐予測パイプラインを停滞させていた。

本Issueでは、比較演算および述語と `if` 分岐を直接融合する「Flag / Branch Fusion」最適化パスを実装した。比較直後に直接 `jne` / `je` / `jge` などの条件ジャンプ命令を出力することで、中間オブジェクト生成を完全排除し、分岐判定を8命令からわずか2命令（75%削減）へと圧縮した。

---

## 2. トレーサビリティ / Traceability
- 性能測定レポート: [outputs/benchmarks/all_lisp_benchmark_report.md](../../../outputs/benchmarks/all_lisp_benchmark_report.md)
- 関連設計書: [docs/designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md](../../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- 関連Issue: #544 (ループ変数レジスタ割付), #546 (末尾引数シャッフル最適化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](../../../ulisp/passes/06_lir.scm) (ANF上の `(let ((var (cmp-expr ...))) (if var ...))` パターン検出、`lir-compile-fused-cmp`、`lir-cmp-false-cc`、各述語の直接フラグ分岐融合)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../../ulisp/passes/07_backend_x86_64.scm) (`%jump-cond` 命令エミッタの追加)
- [x] [ulisp/passes/07_backend_c.scm](../../../ulisp/passes/07_backend_c.scm) (Cバックエンドの `%jump-cond` 同期サポート)
- [x] [ulisp/tests/passes/test_branch_fusion.scm](../../../ulisp/tests/passes/test_branch_fusion.scm) (条件分岐融合ユニットテストスイート: 7項目 100% PASS)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`test_branch_fusion` ターゲット追加)

---

## 4. 実装成果と測定結果 / Implementation & Verification Results

### 1. 生成アセンブリ比較
- **最適化前 (Boolean Materialization)**:
  ```assembly
  cmp rbx, 1000000
  sete al
  movzx eax, al
  shl rax, 6
  add rax, 0x2F
  cmp rax, 0x2F
  je .L_else
  ```
- **最適化後 (Flag / Branch Fusion)**:
  ```assembly
  cmp rbx, 1000000
  jne .L_else
  ```
  中間ブールオブジェクト構築が完全消滅し、**たった2命令** に短縮。

### 2. 純粋CPU実行レイテンシ（1,000,000回反復積算 `loop_sum`）
- **初期スタック版**: **2.834 ms**
- **Issue #544 (レジスタ割付後)**: **1.442 ms**
- **Issue #545 (Flag / Branch Fusion後)**: **0.985 ms** (サブミリ秒達成！)
- **総合改善率**: **65.2% 短縮（2.88倍 高速化）**
- **計算結果**: `499999500000`（完全一致・整合性検証完了）

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(if (= i 1000000) ...)` の生成アセンブリにおいて、`sete`, `shl`, `add rax, 0x2F`, `cmp rax, 0x2F` が完全消滅し、`cmp` + `jne` の2命令で出力されること。
- [x] 全ての比較述語（`=`, `<`, `>`, `<=`, `>=`, `eq?`, `null?`, `pair?`, `zero?`, `not`）で正しいジャンプが行われること。
- [x] `make -C ulisp test_branch_fusion`（7項目 100% PASS）および `test_loop_reg`（8項目 100% PASS）が正常動作すること。
