---
ID: 965
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-25
担当エージェント:
  - IT Specialist (Programming Languages & Compilers / PLC) [Lead]
  - Systems Architect (SA)
  - Software Development (SWD)
  - Software Quality Assurance Specialist
  - Information Security Specialist
ターゲットブランチ: feat/965-futamura-mix-loops-and-case-letrec
---

# [FEAT/ENH] `mix`（`eval-in-stage`）における後方ジャンプループの残余再帰関数生成と `case`・名前付き `let`・`letrec` 対応 (ID: 965)

## 1. 概要・背景 / Summary & Background

`#942` で `eval-in-stage-apply` に `specialize-or-widen` を接続したが、当時のテスト用マイクロ言語には後方ジャンプ（ループ）が存在しないため、静的 PC の再帰呼び出しにおける**メモ化ヒット（循環特殊化）および汎化上限（`8` インスタンス）の挙動が未検証**である。

さらに [eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm) を精査すると、以下の 2 つの構造的課題がある：
1. **循環特殊化における残余関数定義（`letrec`）の未出力**:
   - `eval-in-stage-apply` は、後方ジャンプ等で同じ静的状態（例：`pc = 0`）へ再帰すると `specialize-or-widen` が `status = 'cached`（`stage-lookup-cached-body-sv` は進行中のため `#f`）を返し、`(call-anf target-fn dyn-args...)` を出力する。
   - ところが外側の `status = 'specialized` 完了時は `body-sv` をそのままインライン返却するため、`body-sv` や他の特殊化関数内から `target-fn` を自己/相互再帰呼び出ししていても、`memo` に蓄積された `(define (spec-fn dyn-params...) res-pay)` 群（`spec-memo-residual-fns`）が最終残余 AST（`letrec`）へ出力されず、自己再帰ループを実行できない。
   - あわせて、`structural-step?` が `#f` となる定数テーブルのインデックス遷移（PC 前進・後方ジャンプ等）では、`*max-spec-depth*`（`4`）に先に到達してしまい `*max-spec-instances*`（`8`）を使い切る前に `widened` へ落ちるケースがある点も整理が必要である。
2. **実インタプリタ向け必須 Scheme 構文の不足**:
   - `eval-in-stage`、`bta-infer-expr`、および `bta-annotate-ast-recursive` が `if` / `begin` / `define` / `cond` / `and` / `or` / `let` / `let*` / `lambda` のみにしか対応しておらず、`case`（バイトコードのオペコード・ディスパッチ等）・名前付き `let` `(let loop (...) ...)`・`letrec`（相互再帰クロージャ）を段階評価・BTA 推論できない。

再帰やクリーネ閉包 `*` を含む PEG インタプリタの第 1 二村射影（[Issue #950](../950-verify-first-futamura-projection-peg-staging-via-mix-against-emit-scheme.md)）を実現する前提条件として、後方ジャンプループを含む純粋・一階関数型インタプリタでの停止性および残余再帰関数（`letrec`）生成を確立した（`set!`・破壊的ベクタ更新を前提とする命令型 VM の射影および第 2 射影適用は本 Issue のスコープ外）。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [Issue #942](942-connect-specialize-or-widen-in-eval-in-stage-apply-for-futamura-mix.md)（`specialize-or-widen` 接続と第 1 二村射影実証）
- [Issue #885](885-demonstrate-e2e-first-futamura-projection-on-micro-language.md)（マイクロ言語による第 1 二村射影ベンチマーク基盤）
- [Issue #879](879-implement-stage-poly-lower-nanopass-partial-evaluator.md)（`stage-poly-lower` 部分評価・残余 ANF 正規化）
- [Issue #877](877-implement-specialization-memoization-and-widening-engine.md)（`specialize-or-widen`・`*max-spec-instances* = 8` 仕様）
- [Issue #950](../950-verify-first-futamura-projection-peg-staging-via-mix-against-emit-scheme.md)（Direct-Style PEG インタプリタ × `mix` 段階化 — 本 Issue が前提条件）

### 影響範囲・変更対象ファイル
- [x] [eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm)（`case` / 名前付き `let` / `letrec` / `list-ref` の `eval-in-stage`・`bta-infer-expr`・`bta-annotate-ast-recursive` 対応、PSDS リーフパラメータ化、循環特殊化時の残余 `letrec` 生成、および `eval-residual-anf-expr` での残余 `letrec` / 多引数クロージャ適用対応）
- [x] [test_futamura_projection.scm](../../../ulisp/tests/test_futamura_projection.scm)（Group 4: `case` / 名前付き `let` / `letrec` 段階評価と BTA 整合性、Group 5: 後方ジャンプループ付きバイトコードインタプリタ射影テスト、Group 6: `*max-spec-instances*` 超過時の widening 停止性テスト追加）

---

## 3. アーキテクチャ・詳細設計 / Architecture & Detailed Design

> [!IMPORTANT]
> **ULisp セルフホスト制約（CWE-400・No `set!`・固定アリティ）の遵守**: `ulisp/compiler/eval_in_language.scm` はセルフホスト対象コンパイラモジュールであるため、ローカル変数への `set!` を一切使わず `cons` セルの `set-car!` で環境・カウンタを更新し、既存のリソース上限（`*ctfe-default-step-limit*`, `*ctfe-default-depth-limit*`）を維持している。

### 3.1 `case`・名前付き `let`・`letrec` の段階評価と BTA 推論

1. **`case` (`stage-desugar-case`)**:
   - `(case key-expr ((d1 d2 ...) body ...) ... (else body ...))` を `(let ((__case_key key-expr)) (cond ((or (equal? __case_key 'd1) (equal? __case_key 'd2) ...) body ...) ... (else ...)))` に脱糖して評価する。
   - これにより `Now` ステージおよび `Later` ステージ（静的キー時の dead-branch 消去＋動的キー時の残余 `if` 生成）の双方が既存プリミティブのみで完結する。
2. **名前付き `let` (`stage-desugar-named-let`)**:
   - `eval-in-stage` の `((let let-anf) ...)`、および `bta-infer-expr` / `bta-annotate-ast-recursive` において `(symbol? (cadr expr))` を判定し、`(letrec ((name (lambda (v1 ...) body ...))) (name e1 ...))` へ脱糖して `letrec` 経路で処理する。
3. **`letrec` (`eval-in-stage-letrec` / `stage-bind-rec-specs`)**:
   - `%ctfe-closure` の 6 要素目に自己・相互再帰定義一覧 `rec-specs` を保持する純粋関数的表現を採用し、適用時に `stage-bind-rec-specs`（`Later`）/ `ctfe-env-extend`（`Now`）で全相互再帰関数を再束縛する。
   - `Later` ステージで非特殊化参照が残る場合には `stage-expr-mentions-sym?` で到達可能な未特殊化関数定義のみを残余 `(letrec ...)` へ出力する。

### 3.2 後方ジャンプ・循環特殊化の残余 `letrec` 生成と停止性

1. **PSDS リーフパラメータ化 (`stage-parameterize-args` / `stage-extract-args-dyn-leaves`) & `stage-sv->residual-expr`**:
   - `(cons dyn_n (cons dyn_acc '()))` のような PSDS（Partially Static Data Structure）引数を特殊化する際、静的スパインを保ったまま動的リーフのみを仮引数（`st$0`, `st$1`）へ展開し、`call-anf` に動的リーフ値のみを引き渡す。
2. **循環特殊化の検出 (`*active-spec-cyclic-fns-cell*`) と残余 `letrec` 出力 (`stage-collect-reachable-residual-defs`)**:
   - `'cached` ヒット時に `cached-sv = #f`（評価中ループ再入）となった `target-fn` を `stage-mark-cyclic-spec-fn!` で記録し、該当 `target-fn` 完了時はインライン展開ではなく `(call-anf target-fn dyn-arg-payloads...)` を返す。
   - `stage-poly-lower` 完了時に `stage-collect-reachable-residual-defs` で `norm-root` から到達可能な特殊化関数定義群を収集・ANF 正規化し、1 つ以上存在する場合のみ `(letrec ((spec-fn (lambda (params...) norm-body)) ...) norm-root)` を構築する（非循環の既存 Group 1〜3 はフラット AST のまま後方互換 100% 維持）。
3. **残余評価器 `eval-residual-anf-expr` の拡張**:
   - `(letrec ...)`（相互再帰 `%res-closure`）・多引数適用・`not`/`<=`/`>=`/`eq?`/`equal?`/`cons`/`car`/`cdr`/`cadr`/`caddr`/`null?`/`pair?`/`list-ref` を評価可能とした。
4. **定数プログラムテーブル巡回時の深度リセット (`stage-has-non-growing-compound-static?`)**:
   - `prog` 等の複合静的引数（`pair-weight > 0`）が非増加のまま遷移する場合に `call-spec-depth` を 0 にリセットし、有限 PC 巡回が `*max-spec-depth*`（4）で早期 widening されず `*max-spec-instances*`（8）まで循環特殊化を完結させ、8 超過時は `specialize-or-widen` の widening で確実に停止するようにした。

---

## 4. 実装結果と品質検証 / Implementation & Verification

- `make -C ulisp compiler test_futamura_projection test_stage_poly_lower test_eval_in_stage test_eval_in_language test_specialization_widening test_bta_lattice test_nanopass_stagepoly_lang test_grammar_conformance_assertion test_residual_contification test_pass_manager test_lint_sexpr`: 全 PASS
- `make check_format && make static_analysis && make py_compile`: 全 PASS（`mypy --strict` 617 ファイル 0 エラー）

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `eval-in-stage`・`bta-infer-expr`・`bta-annotate-ast-recursive` が `case`・名前付き `let`・`letrec` を正しく段階評価・BTA 推論できること
- [x] 後方ジャンプ（`JUMP` / `JZ-TOP` 等）を含むバイトコードインタプリタを `mix`（`stage-poly-lower`）で射影した際、展開爆発せず停止し、`spec-memo-residual-fns` から再帰的な残余関数（`letrec`）が生成され、全オペコードが消去されていること
- [x] `*max-spec-instances*`（`8`）を超える動的/静的状態展開に対して `specialize-or-widen` の widening が機能し、有限ステップで停止すること
- [x] 生成された残余 `letrec` コードの評価結果が複数の動的入力（`n = 0, 1, 5, 10` 等）に対して元のインタプリタ直接実行結果と完全一致し、既存の `test_futamura_projection` Group 1〜3 および関連テストに回帰がないこと
- [x] `make -C ulisp test_futamura_projection test_stage_poly_lower test_eval_in_stage test_specialization_widening test_lint_sexpr` および品質ゲートが全 PASS すること
