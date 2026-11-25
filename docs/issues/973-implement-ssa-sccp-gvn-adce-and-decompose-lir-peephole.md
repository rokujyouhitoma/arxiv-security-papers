---
ID: 973
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] L_mir_ssa 上の共通 SSA データフロー最適化群（SCCP・SSA-GVN・ADCE）の実装と 133_lir_peephole.scm のパス分解 (ID: 973)

## 1. 概要 / Summary

`L_mir_ssa`（Braun SSA）上に Scheme/C99 共通のミドルエンド最適化として、疎条件付き定数伝播（SCCP）、大域値ナンバリング（SSA-GVN）、SSA 値ベース ADCE（Aggressive DCE）を実装する。
あわせて 1,177 行の `133_lir_peephole.scm` に同居している 4 処理（定数畳み込み・ウィンドウ規則・冗長拡張削除・DSE）を独立パスへ分解し、`pass_manager.scm` の解析キャッシュ・固定点ドライバで統合管理する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #966](966-separate-mir-ssa-and-machine-lir-for-unified-middle-end.md)
  - [Issue #840](closed/840-automate-analysis-cache-invalidation-and-recomputation-in-nanopass.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [133_lir_peephole.scm](../../ulisp/lir/133_lir_peephole.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [ ] [c_driver.scm](../../ulisp/driver/c_driver.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/973-ssa-sccp-gvn-adce-and-peephole-split`

1. `L_mir_ssa` 上にワークリストベースの SCCP、支配木走査による SSA-GVN、および Use-Def ベース ADCE を実装する。
2. `133_lir_peephole.scm` の 4 処理を独立パスへ分離し、`pass_manager.scm` の `run-pass-fixpoint` と解析契約で制御する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] SCCP / SSA-GVN / ADCE が Scheme/C99 共通ミドルエンドで動作し、差分テストで意味等価性が確認されること
- [ ] `133_lir_peephole.scm` が単一責務の独立パス群へ整理されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
