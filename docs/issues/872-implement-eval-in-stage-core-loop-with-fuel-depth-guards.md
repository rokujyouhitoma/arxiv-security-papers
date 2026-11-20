---
ID: 872
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] eval-in-stage コアループと Fuel/Depth リソースバウンドガードの実装 (ID: 872)

## 1. 概要 / Summary
DSN-33-03 §3.5 および §2.6 に基づき、ステージ多相評価器の再帰コアループ `eval-in-stage` を実装する。CWE-400 ガードとしてステップ数（`fuel`）と再帰深度（`depth`）を厳格に監視し、多層タワーにおける相対ステージレベル遷移（減算規約）を導入する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §2.6, §3.5](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#35-eval-in-stage-コアループ仕様と安全リソースバウンド-fueldepth)
- 関連 Issue: #825 (CTFE Fuel)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/eval_in_language.scm](ulisp/compiler/eval_in_language.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/872-implement-eval-in-stage-core-loop-with-fuel-depth-guards`

1. `eval-in-stage` をリファクタリングし、`dict`, `env`, `expr`, `fuel`, `depth` を受け取る汎用ステージ多相ループとする。
2. `fuel <= 0` または `depth <= 0` 検知時に `signal-csp-error` を呼び出し、無限ループを遮断。
3. 外側のメタ層通過ごとに `stage-level` を 1 減算し、0 で `Later` 辞書へ切り替える相対レベル方式を実装。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Fuel 枯渇および深度上限超過時に安全に停止すること。
- [ ] 相対ステージレベル遷移が正しく機能し、多層タワーが崩壊しないこと。
- [ ] `make py_compile` が PASS すること。
