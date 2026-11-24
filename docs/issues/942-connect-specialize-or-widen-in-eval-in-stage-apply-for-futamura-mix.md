---
ID: 942
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 混合器 (mix) の完成：`specialize-or-widen` の `eval-in-stage-apply` 接続と第1二村射影実証・DSN-33-24 Phase I3 整合化 (ID: 942)

## 1. 概要 / Summary

`ulisp/compiler.scm` において、多変量特殊化のメモ表と汎化を行う `specialize-or-widen` は単体テストから手組みビルダー経由で呼ばれているのみで、`eval-in-stage-apply` の `Later` 段からは呼ばれておらず、トップレベルのユーザー定義関数を展開せず残余呼び出しをそのまま出力している。また `ulisp/tests/test_futamura_projection.scm` の「第1射影」も、インタプリタ `micro-interp-eval` を部分評価するのではなく手書き変換器 `micro-bytecode->stage-poly` との照合にとどまっている。

なお、`stage-known-primitive?` および `stage-pure-effect-free?` には既に `assq` / `memq` が登録済みであることを確認済みである。本 Issue では `eval-in-stage-apply`（`Later` 段）から `specialize-or-widen` へ接続し、未改変 `micro-interp-eval` に対する第1二村射影を手書き版オラクルで検証・実証するとともに、[DSN-33-24](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md) の Phase I3 ステータス整合を行う（第2・第3射影の自己適用は対象外）。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [DSN-33-24 §8.1](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md#L503-L510)
  - [DSN-33-21](../designs/DSN-33-21-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [Issue #877](closed/877-implement-specialization-memoization-and-widening-engine.md)
  - [Issue #885](closed/885-demonstrate-e2e-first-futamura-projection-on-micro-language.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [compiler.scm](../../ulisp/compiler.scm) (`eval-in-stage-apply`, `specialize-or-widen`, `stage-known-primitive?`)
- [ ] [test_futamura_projection.scm](../../ulisp/tests/test_futamura_projection.scm) (未改変 `micro-interp-eval` 入力化・手書き版オラクル比較)
- [ ] [test_specialization_widening.scm](../../ulisp/tests/test_specialization_widening.scm)
- [ ] [cogen.scm](../../ulisp/workbench/cogen.scm) (双対検証対象・手書き維持)
- [ ] [DSN-33-24](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md) (§8.1 `Phase I3` ステータスを一旦「部品完了・未接続」に是正後、完了時に「完了」へ同期)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/942-connect-specialize-or-widen-in-eval-in-stage-apply`

1. [DSN-33-24](../designs/DSN-33-24-ulisp_futamura_projection_scheme_interpreter_synthesis_architecture.md) §8.1 の `Phase I3` ステータスを「部品完了・未接続」へ訂正する（本 Issue 完了後に「完了」へ戻す）。
2. `eval-in-stage-apply`（`Later` 段）において、トップレベルのユーザー定義関数を「少なくとも 1 つの引数が静的」な形で呼び出す際に `specialize-or-widen` を経由させる（静的引数を束縛して関数本体を `Later` 段で評価するビルダーを渡し、既存の上限「インスタンス 8 個・深さ 5」と汎化で停止性を保証する）。
3. `ulisp/tests/test_futamura_projection.scm` に未改変の `micro-interp-eval` を渡すように書き換え、既存の手書き版 `micro-bytecode->stage-poly` を期待値の判定基準（オラクル）として再利用する（詳細実装・検証手順は `polish-issue` にて精緻化する）。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] 残余コードにオペコード記号（`PUSH-CONST` / `LOAD-VAR` / `ADD` 等）が残らないこと。
- [ ] 未改変 `micro-interp-eval` の部分評価結果が手書き版 `micro-bytecode->stage-poly` の結果と一致し、`cogen` 出力との双対検証が可能であること。
- [ ] `DSN-33-24` §8.1 の `Phase I3` ステータスが実態と整合して更新されていること（詳細ゲートは `polish-issue` 時に確定）。
