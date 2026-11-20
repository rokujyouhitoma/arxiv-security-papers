---
ID: 888
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT] 旧 ctfe_eval の eval-in-stage (Now dict) への一本化と二重実装解消 (ID: 888)

## 1. 概要 / Summary
DSN-33-03 §3.6（単一ソース意味論オラクル）および §8.1 (Phase P5) に基づき、`ulisp/compiler/eval_in_language.scm` 内で旧来から存在していたマクロ展開・DSL 定数畳み込み用の `ctfe-eval` ループを、新設されたステージ多相評価器 `eval-in-stage`（`<stage-dict>` の `Now` 辞書評価モード）へと一本化・統合する。
重複したインタプリタループの保守負担を解消し、コンパイル時計算のセマンティクスを完全に統一する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §3.2, §3.6](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#32-now-辞書即時計算ctfeオラクル評価)
  - [DSN-33-01 Phase 7](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md#phase-7dsn-33-03-ステージ多相部分評価パスの常設統合と-ctfe-一本化)
- 関連 Issue: #870 (Stage-Dict), #872 (Eval-in-Stage), #873 (Single-Source Oracle)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm)
- [x] [ulisp/tests/test_eval_in_language.scm](../../ulisp/tests/test_eval_in_language.scm)
- [x] [ulisp/tests/test_single_source_oracle.scm](../../ulisp/tests/test_single_source_oracle.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/888-consolidate-legacy-ctfe-eval-into-stage-poly-evaluator`

1. **`ctfe-eval` の `eval-in-stage` 委譲化**:
   - `ulisp/compiler/eval_in_language.scm` の `(ctfe-eval expr env fuel depth)` の内部実装を、新設の `Now` 辞書を用いた `eval-in-stage` 呼び出しに置き換える：
     ```scheme
     (define (ctfe-eval expr env fuel depth)
       (let ((now-d (make-now-dict)))
         (eval-in-stage now-d env expr fuel depth)))
     ```
2. **`ctfe-try-reduce` および `eval-in-language` の配線整理**:
   - `ctfe-try-reduce` も同様に `eval-with-now-oracle-opt` または `eval-in-stage` を直接利用するようリファクタリング。
   - `eval-in-language` (Issue #825) の CTFE バックエンドをステージ多相評価器へ完全同期。
3. **互換性および回帰検証**:
   - `test_eval_in_language.scm` および `test_single_source_oracle.scm` を実行し、既存の定数畳み込み、型注釈簡約、マクロ展開が 100% 同一の結果を返すことを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 旧 `ctfe-eval` が `eval-in-stage (Now dict)` をバックエンドとして利用し、独立した重複インタプリタループが完全に消去されていること。
- [ ] 既存の CTFE 全テスト（`test_eval_in_language.scm`, `test_single_source_oracle.scm` 等）が 100% PASS すること。
- [ ] コンパイラのブートストラップ不動点が維持されること。
