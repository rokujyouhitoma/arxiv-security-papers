---
ID: 523
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-10-15
---

# [FEAT/ENH] 基本ブロック引数 (Block Arguments) 型 SSA 中間表現と Braun 法オンザフライ構築の実装 (ID: 523)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 6 SSA & Braun法) で提唱される「基本ブロック引数（Basic Block Arguments）型 SSA」および「Braun らのオンザフライ SSA 構築法」を ULisp の低水準 IR（LIR）層へ導入する。
従来の LLVM 流の変則的な $\phi$ 疑似命令ノードを排除し、MLIR や Swift IL と同様に各基本ブロックが仮引数シグネチャを持ち、ジャンプ命令が実引数を渡す構造を採用する。これにより、Scheme の末尾呼び出しおよび CPS 的意味論と LIR を 1:1 に直結させるとともに、支配フロンティアの事前計算なしに AST/ANF 走査中に最小 SSA 形式を高速かつ決定論的に構築する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.1節 Block Arguments SSA & Braun法)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #499: ULisp コンパイラへの ANF (A-Normal Form) 正規化および CP0 最適化パスの実装
  - Issue #502: ULisp コンパイラへの低レベルIR (LIR) の導入とバックエンド分離

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (基本ブロック引数型 SSA LIR 表現への拡張)
- [x] [ulisp/passes/04_anf.scm](../../ulisp/passes/04_anf.scm) (Braun 法によるオンザフライ変数束縛解決)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (ブロック引数ジャンプのアセンブリコード生成)
- [x] [ulisp/passes/07_backend_aarch64.scm](../../ulisp/passes/07_backend_aarch64.scm) (AArch64 向けブロック引数ハンドリング)
- [x] [ulisp/passes/07_backend_c.scm](../../ulisp/passes/07_backend_c.scm) (Portable C 向けブロック引数ハンドリング)
- [x] [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) (LIR 仕様書の改定)
- [x] [ulisp/tests/passes/test_lir.scm](../../ulisp/tests/passes/test_lir.scm) (ブロック引数 SSA 単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/523-ulisp-block-arguments-ssa-and-braun-construction`

1. **基本ブロック引数型 LIR 構文仕様の策定**:
   - 基本ブロック構文: `(%block <label> (<param1> ...) <instr> ...)`
   - ジャンプ命令構文: `(%jump <label> (<arg1> ...))`
   - 条件分岐構文: `(%jump-if <cond> <then_label> (<then_args> ...) <else_label> (<else_args> ...))`
2. **Braun らのアルゴリズム（2013）の実装**:
   - 変数読み出し `readVariable` と代入 `writeVariable` を基本ブロックごとに追跡。
   - 未解決ブロックには空のブロック引数プロキシを遅延配置し、ブロックの先行エッジ確定時（`sealBlock`）に再帰的に実引数を結線して最小 SSA を生成。
3. **バックエンドでのレジスタ割り当て・引数渡し**:
   - ブロック間ジャンプ実引数をターゲットレジスタおよびスタック位置へ平行代入（Parallel Copy）として割り当て、疑似 $\phi$ 命令の消去フェーズを完全不要化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] $\phi$ 疑似命令を介さず、Block Arguments 形式で LIR が表現・出力されること。
- [x] Braun 法により、支配フロンティア計算なしで最小・刈り込み済み SSA がオンザフライ生成されること。
- [x] x86-64 および AArch64 バックエンドテストが全件 PASS し、3 段階ブートストラップの決定論的不動点が維持されること。
