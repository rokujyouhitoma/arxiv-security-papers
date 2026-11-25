---
ID: 967
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 フロントエンド lower_to_lir.scm（5,009行）の責務別パス分割（MIR 生成・SysV ABI 展開・Inline Asm 正規化） (ID: 967)

## 1. 概要 / Summary

5,009 行に肥大化した `lower_to_lir.scm`（および 2,967 行の `sema.scm` 境界）が、型レイアウト・ビットフィールド・単一評価アドレス計算・SysV AMD64 構造体 ABI・`<stdarg.h>`・AT&T→Intel インライン asm 変換・物理レジスタ LIR 生成を 1 パスで同時実行しており、C99 コードが中水準の最適化を一切通らず低水準 LIR に落ちている。
本 Issue では、`c99_lower_mir` / `c99_lower_abi` / `c99_lower_inline_asm` の責務別パスへ分割し、C99 側も共通 SSA ミドルエンドの恩恵を受けられる構造へ整理する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #966](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [c_driver.scm](../../ulisp/driver/c_driver.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [lower_to_lir.scm](../../ulisp/frontend_c/lower_to_lir.scm)
- [ ] [sema.scm](../../ulisp/frontend_c/sema.scm)
- [ ] [c_driver.scm](../../ulisp/driver/c_driver.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/967-split-c99-lower-to-lir`

1. C-AST から仮想レジスタ SSA IR を生成する `c99_lower_mir` パスを切り出す。
2. SysV 構造体値渡し/返却・`va_arg`・ビットフィールド展開を担当する `c99_lower_abi` と、AT&T→Intel 構文変換・制約正規化を担当する `c99_lower_inline_asm` を分離する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `lower_to_lir.scm` が責務別モジュール/パスへ分割され、`pass_manager.scm` / `c_driver.scm` と整合すること
- [ ] 既存の C99 テストスイート（構造体・`stdarg`・`setjmp/longjmp`・`inline_asm`・Lua テスト等）が全 PASS すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
