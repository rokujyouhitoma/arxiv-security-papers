---
ID: 875
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 動的分岐配下の純粋性解析と投機的副作用・例外の自動 Later 降格 (ID: 875)

## 1. 概要 / Summary
DSN-33-03 §4.2 に基づき、動的条件分岐（Later `if`）配下に含まれる Now 式の純粋性（Purity）を解析し、副作用（I/O, 状態更新）や例外（ゼロ除算）を伴う式を自動的に Later（残余コード）へと降格させ、Speculative Trap（投機的誤発火）を根絶する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §4.2](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#42-越境規則cross-stage-persistenceと動的分岐下の副作用例外降格規約)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/dataflow.scm](ulisp/compiler/dataflow.scm)
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/875-implement-purity-analysis-and-speculative-trap-demotion`

1. プリミティブおよび式の純粋性述語 `pure-effect-free?` を実装。
2. 動的分岐コンテキスト下での Now 評価時に、非純粋式または例外リスク演算（除算など）を検知して自動 Later 降格。
3. 実行時の副作用順序（Effect Ordering）と完全に一致させる。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 動的 if の片側節にあるゼロ除算 `(/ 1 0)` がコンパイル時クラッシュせず、残余コードへ降格されること。
- [ ] `make py_compile` が PASS すること。
