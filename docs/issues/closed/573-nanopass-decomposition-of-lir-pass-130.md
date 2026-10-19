---
ID: 573
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] LIR パス (130_lir.scm) の機能責務別ナノパス分割（プリミティブ命令選択モジュールの独立化） (ID: 573)

## 1. 概要 / Summary
現在 `ulisp/passes/130_lir.scm` は 1,721 行 (73KB) に達する最大のメガパスとなっており、即値解決、環境管理、基本プリミティブ命令選択、クロージャ生成、スタック割り当て、継続呼び出し・in-place シャッフルループ、制御構文、多値・例外・call/cc 等の多様な責務が一体化している。
本 Issue では、Nanopass コンパイラ設計思想に基づき、`130_lir.scm` からプリミティブ命令選択責務（zero-arg, unary, binop, triop, raw-syscall）を独立パス `129_lir_primitives.scm` として抽出し、`130_lir.scm` の行数を約 460 行大幅削減して責務境界を明確化する。また対応する単体テスト `test_129_lir_primitives.scm` を配備して 1:1 完全対応テスト網羅を維持する。

---

## 2. トレーサビリティ / Traceability
- Nanopass Framework 原則
- DSN-33 コンパイラアーキテクチャ仕様
- Issue #571 (Pass 128 分離実績)
- Issue #572 (1:1 テストスイート網羅)
- Issue #575 (Makefile エンジン呼び出し一元化)
- 関連資料: [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/129_lir_primitives.scm](../../ulisp/passes/129_lir_primitives.scm) (新規: プリミティブ命令選択)
- [x] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (プリミティブ命令選択の切り出し・リファクタリング)
- [x] [ulisp/tests/passes/test_129_lir_primitives.scm](../../ulisp/tests/passes/test_129_lir_primitives.scm) (新規: 1:1 単体テスト)
- [x] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) (回帰確認)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`PASSES_LIB` および `NANOPASS_TESTS` リスト更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/573-nanopass-decomposition-of-lir-pass-130`

1. **`129_lir_primitives.scm` の抽出**:
   - `lir-compile-zero-arg` (行 78〜101)
   - `lir-compile-unary` (行 102〜296)
   - `lir-compile-operand-for-op` (行 297〜311)
   - `lir-compile-binop` (行 312〜455)
   - `lir-compile-triop` (行 456〜501)
   - `lir-compile-raw-syscall` (行 502〜539)
   上記関数群を `passes/129_lir_primitives.scm` に移動。
2. **`ulisp/Makefile` の連動更新**:
   - `PASSES_LIB` において `passes/128_lir_branch_fusion.scm` の直後、`passes/130_lir.scm` の直前に `passes/129_lir_primitives.scm` を配置。
   - `NANOPASS_TESTS` に `tests/passes/test_129_lir_primitives.scm` を追加（計 23 パス）。
3. **1:1 テストスイートの配備**:
   - `tests/passes/test_129_lir_primitives.scm` で各プリミティブ命令選択関数の動作を検証。
4. **回帰検証**:
   - `make -C ulisp test_all_passes` および AOT テスト群の正常動作を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `130_lir.scm` からプリミティブ命令選択責務が `129_lir_primitives.scm` に分離され、コードサイズが約 460 行削減されていること
- [x] `ulisp/Makefile` の `PASSES_LIB` および `NANOPASS_TESTS` に Pass 129 が正しく登録されていること
- [x] `tests/passes/test_129_lir_primitives.scm` が新設され、PASS すること
- [x] 全 23 パステストおよび全 AOT テストが 100% PASS すること
