---
ID: 977
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 投機的ループ・アンチェック化（Loop Unswitching / 型タグ検査・配列境界チェックのループ外巻き上げ）の実装 (ID: 977)

## 1. 概要 / Summary

ホットループ内部で反復ごとに実行される型タグ検査（`emit-lir-bin-tag-check!`）や配列・ベクタ境界チェック（Scheme `vector-ref` および C99 `--sanitize-bounds`）をループ手前へ 1 回だけ持ち出し、チェックを完全に排除した高速パスとフォールバックパスへ分岐させる Loop Unswitching / Bounds Check Elimination (BCE) パスを実装する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #976](976-implement-ssa-loop-analysis-and-licm-pass.md)
  - [Issue #930](closed/930-implement-c99-bounds-checking-sanitizer-mode.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)
- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm)
- [ ] [132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/977-loop-unswitching-and-bce`

1. ループ不変条件（型タグ・ベクタ長・誘導変数範囲）を検出し、ループ前で一括検査して高速版/汎用版ループへ分岐する Loop Unswitching を実装する。
2. 誘導変数レンジと不変配列長から境界チェックが恒真となるケースで内部チェックを消去する BCE を実装する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] ホットループ内の重複型タグ検査・境界チェックがループ外へ巻き上げ・消去されること
- [ ] Vector 走査および `--sanitize-bounds` 有効時ベンチマークの大幅高速化が確認されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
