---
ID: 878
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Nanopass 中間言語 L-StagePoly および L-Residual-ANF の定義 (ID: 878)

## 1. 概要 / Summary
DSN-33-03 §6.1 および §6.2 に基づき、メタ構文（`stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote`）を持つ `L-StagePoly` と、それらを文法から完全除外（`-`）した純粋 ANF 言語 `L-Residual-ANF` を Nanopass フレームワーク上に定義する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §6.1, §6.2](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#6-nanopass-差分言語extendsによる階層消去証明)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](ulisp/compiler/nanopass_meta.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/878-define-nanopass-languages-l-stagepoly-and-l-residual-anf`

1. `define-language L-StagePoly` を記述し、メタステージ構文を文法に導入。
2. `(extends L-StagePoly)` で `define-language L-Residual-ANF` を定義し、メタ構文を文法的に除外（`-`）。
3. ANF ノード（`let-anf`, `let-call`, `atom-value`）を規律化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Nanopass の言語バリデータが両言語の文法規則を正しく解釈すること。
- [ ] `make py_compile` が PASS すること。
