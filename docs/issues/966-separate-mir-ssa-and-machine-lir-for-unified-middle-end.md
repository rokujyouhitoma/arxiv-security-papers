---
ID: 966
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] L_mir_ssa（仮想レジスタ SSA）と L_lir_mach（物理レジスタ機械 LIR）の 2 層分離と Scheme/C99 共通ミドルエンド統合 (ID: 966)

## 1. 概要 / Summary

現在 `L_lir_core` / `L_lir_raw` に物理レジスタ（`%rax`/`%rsp`）・仮想レジスタ（`(%reg x)`）・SSA ブロック引数・フラットラベルが混在しており、`130_lir.scm` の段階で既にスタック退避中心の物理レジスタコードへ落ちている。
本 Issue では、物理レジスタ非依存の `L_mir_ssa`（Braun SSA）と、ABI / Managed Runtime Lowering・レジスタ割付後の `L_lir_mach` の 2 層に明確分離し、Scheme（`L_lifted`）と C99（`C-AST`）の双方を `L_mir_ssa` へ合流させて共通のミドルエンド最適化基盤を構築する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #835](closed/835-separate-core-machine-lir-from-managed-runtime-dialect.md)
  - [Issue #827](closed/827-generalize-pass-132-braun-ssa-for-arbitrary-cfg-and-goto.md)
  - [Issue #961](961-introduce-linear-scan-register-allocation-for-scheme-lir.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [lir_lang.scm](../../ulisp/lir/lir_lang.scm)
- [ ] [lir_verifier.scm](../../ulisp/lir/lir_verifier.scm)
- [ ] [130_lir.scm](../../ulisp/lir/130_lir.scm)
- [ ] [131_lower_managed_dialect.scm](../../ulisp/lir/131_lower_managed_dialect.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/966-separate-mir-ssa-and-machine-lir`

1. `lir_lang.scm` / `lir_verifier.scm` に仮想レジスタ専用 SSA 中間言語 `L_mir_ssa` と物理レジスタ確定後 `L_lir_mach` の契約を定義する。
2. `130_lir.scm` および C99 Lowering の出力を `L_mir_ssa` へ統合し、Managed Lowering（`131_lower_managed_dialect.scm`）およびレジスタ割付との境界を整備する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `L_mir_ssa` と `L_lir_mach` の言語定義・Verifier 検査が分離され、パス連続性検証が通ること
- [ ] Scheme / C99 の両フロントエンドから `L_mir_ssa` 経由で既存テストスイートが全 PASS すること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
