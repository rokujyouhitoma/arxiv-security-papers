---
ID: 877
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 特殊化メモ化エンジンとハードリミット・一般化（Widening）の実装 (ID: 877)

## 1. 概要 / Summary
DSN-33-03 §5.1, §5.2, §5.3 に基づき、再帰関数やインタプリタの展開停止性を保証する特殊化メモ化エンジンを実装する。`MAX_SPEC_INSTANCES=8`, `MAX_SPEC_DEPTH=4` をハードリミットとして課し、上限超過時には一般化（Widening）を行って残余関数（`define-residual-fn`）へ切り離す。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §5.1, §5.2, §5.3](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#5-特殊化エンジンと停止性保証hard-limits--generalization)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)
- [ ] [ulisp/compiler/scope.scm](ulisp/compiler/scope.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/877-implement-specialization-memoization-and-widening-engine`

1. キー $\langle \mathrm{FuncSymbol},\; \Pi_{\text{static}}(\mathrm{Args}) \rangle$ によるハッシュテーブルを配備。
2. 特殊化インスタンス数と再帰深度をトラッキング。
3. しきい値超過時に静的引数を動的引数へ降格し、汎用残余関数の直接呼び出しへと変換。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 多相再帰関数が無限展開に陥らず、8インスタンス以内で停止すること。
- [ ] 残余関数が MIR 上に正しく分離・発行されること。
- [ ] `make py_compile` が PASS すること。
