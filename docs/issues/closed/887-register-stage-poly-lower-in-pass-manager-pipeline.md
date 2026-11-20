---
ID: 887
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Pass Manager への pass-075-stage-poly-lower 常設登録と最適化レベル連動 (ID: 887)

## 1. 概要 / Summary
DSN-33-03 §2.6, §8.1 (Phase P5) および DSN-33-01 Phase 7 に基づき、現在テストスイート等からオプトイン呼び出しされているステージ多相部分評価 Nanopass（`stage-poly-lower`）を、Pass Manager の標準パイプライン定義（`init-default-pass-registry!`）へ `pass-075-stage-poly-lower` として常設登録する。
最適化レベル（`-O1/-O2`）または入力 AST 内のメタ構文（`stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote` 等）の有無を検知して条件付き実行し、AOT コンパイル時に二村射影（Tower Collapse）を自動発火可能にする。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §2.6, §8.1 (Phase P5)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#26-多層タワーn-ステージにおけるレベル遷移規則相対レベル方式-vs-パイプライン連鎖方式)
  - [DSN-33-01 Phase 7](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md#phase-7dsn-33-03-ステージ多相部分評価パスの常設統合と-ctfe-一本化)
- 関連 Issue: #879 (Stage-Poly-Lower), #880 (Grammar Conformance Assertion), #885 (Tower Collapse)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/pass_manager.scm](../../ulisp/compiler/pass_manager.scm)
- [x] [ulisp/compiler/frontend_passes.scm](../../ulisp/compiler/frontend_passes.scm)
- [x] [ulisp/tests/test_pass_manager.scm](../../ulisp/tests/test_pass_manager.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/887-register-stage-poly-lower-in-pass-manager-pipeline`

1. **メタ構文検知述語の実装 (`contains-stage-meta-syntax?`)**:
   - `ulisp/compiler/frontend_passes.scm` に、AST を高速再帰走査して `stage-now`, `stage-later`, `stage-lift`, `stage-quasiquote`, `stage-unquote` が存在するか判定する述語を配備。
2. **`pass-075-stage-poly-lower` のディスクリプタ定義**:
   - `ulisp/compiler/pass_manager.scm` の `init-default-pass-registry!` に以下を登録：
     ```scheme
     (register-pass!
       (make-pass-descriptor 'pass-075-stage-poly-lower "Stage-Polymorphic Partial Evaluator" 'frontend 1
         (lambda (forms)
           (if (or (>= (pass-opt-level) 1) (contains-stage-meta-syntax? forms))
               (stage-poly-lower-all forms)
               forms))
         'stage-poly-lower 'L_core 'L-Residual-ANF '(pass-070-anf) #f))
     ```
   - 既存の `vphase = 'stage-poly-lower` ガード（`verify-residual-anf-conformance`）と直結。
3. **`pass-name-table` およびパイプライン一覧への追加**:
   - `*default-pipeline-passes*` において `pass-070-anf` と `pass-080-annotator` の間に配置。
4. **単体テストの策定**:
   - `ulisp/tests/test_pass_manager.scm` において、`pass-075-stage-poly-lower` が登録され、メタ構文を含むプログラムに対して部分評価が自動実行・文法検証されることをアサート。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `pass-075-stage-poly-lower` が Pass Manager の標準パイプラインに登録され、`run-pass-pipeline` で正しく駆動されること。
- [x] メタ構文を含む AST に対して部分評価が自動実行され、`verify-residual-anf-conformance` をパスすること。
- [x] 最適化レベル 0 かつメタ構文なしの場合は余分な処理をスキップすること。
- [x] 既存の全フロントエンドテストおよびセルフホスト不動点検証が 100% PASS すること。
