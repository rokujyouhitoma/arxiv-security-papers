---
ID: 978
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 高水準リスト・ストリーム融合（Loop Fusion / Deforestation）パスの導入 (ID: 978)

## 1. 概要 / Summary

`(map f (map g xs))` や `(fold k z (filter p (map f xs)))` のような連続するリスト・ストリーム走査を単一ループへ融合する Deforestation パスをフロントエンド最適化として導入する。
中間ペア生成と GC 負荷を削減し、`List Alloc & Traverse` 系ワークロードを高速化する。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #971](971-implement-general-inliner-and-frontend-fixpoint-optimization.md)
  - [BASELINE.md](../../ulisp/benchmarks/BASELINE.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [050_cp0.scm](../../ulisp/frontend/050_cp0.scm)
- [ ] [frontend_lang.scm](../../ulisp/frontend/frontend_lang.scm)
- [ ] [pass_manager.scm](../../ulisp/compiler/pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/978-list-and-stream-loop-fusion`

1. `map` / `filter` / `fold` / ストリーム操作の合成パターンを検出し、純粋性・評価順序を保ちつつ単一変換・単一ループへ融合する規則（foldr/build またはストリーム融合）を実装する。
2. `050_cp0.scm` の `map`/`for-each` 展開と協調するパス順序・無効化契約を `pass_manager.scm` に定義する。
3. 詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 連続した `map` / `filter` / `fold` 連鎖から中間リストのヒープ割当が消去されること
- [ ] 副作用を含むラムダ引数時に評価順序が破壊されないことがテストで検証されること
- [ ] `make format` / `make static_analysis` / `make test` および `verify-quality-gates` が全 PASS すること
