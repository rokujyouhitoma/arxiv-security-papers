---
ID: 879
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ステージ多相部分評価 Nanopass (stage-poly-lower) の実装 (ID: 879)

## 1. 概要 / Summary
DSN-33-03 §6.2 および §3.5 に基づき、`L-StagePoly` から `L-Residual-ANF` への変換パス `stage-poly-lower` を実装する。静的項（Now）をすべて評価・消去し、動的項（Later）のみを残余 ANF 構造へと平坦化する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §2.1, §3.3, §6.2](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#62-l-residual-anf-言語定義メタ構文の完全除外--)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/driver.scm](ulisp/compiler/driver.scm)
- [ ] [ulisp/compiler/pass_manager.scm](ulisp/compiler/pass_manager.scm)
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/879-implement-stage-poly-lower-nanopass-partial-evaluator`

1. `define-pass stage-poly-lower : L-StagePoly -> L-Residual-ANF` を宣言。
2. `eval-in-stage (Later 辞書)` を走査ドライバとして結合。
3. 静的分岐を刈り込み、定数式を即値へ畳み込み、動的呼び出しのみを ANF バインディングへ残余化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] メタ構文を含む式から、純粋な `L-Residual-ANF` 構文木が決定論的に導出されること。
- [ ] `make py_compile` が PASS すること。
