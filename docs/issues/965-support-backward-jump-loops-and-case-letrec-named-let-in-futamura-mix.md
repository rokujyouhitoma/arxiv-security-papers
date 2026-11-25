---
ID: 965
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] `mix`（`eval-in-stage`）における後方ジャンプループの残余再帰関数生成と `case`・名前付き `let`・`letrec` 対応 (ID: 965)

## 1. 概要 / Summary

`#942` で `eval-in-stage-apply` に `specialize-or-widen` を接続したが、当時のテスト用マイクロ言語には後方ジャンプ（ループ）が存在しないため、静的 PC の再帰呼び出しにおける**メモ化ヒット（循環特殊化）および汎化上限（`8` インスタンス）の挙動が未検証**である。

さらに [eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm) を精査すると、以下の2つの構造的課題がある：
1. **循環特殊化における残余関数定義の未出力**: `eval-in-stage-apply` は後方ジャンプ等で同じ静的状態（例：`pc = 0`）へ再帰すると `status = 'cached` (`cached-sv = #f`) で `(target-fn dyn-args...)` を出力するが、外側の `status = 'specialized` 完了側が `body-sv` をそのままインライン展開するため、`memo` に記録された `(define (target-fn ...) ...)` 群（`spec-memo-residual-fns`）が最終残余 AST（`letrec` 等）に束縛されず自己再帰呼び出しが未定義のままになる。
2. **実インタプリタ向け必須構文の不足**: `eval-in-stage` / `bta-infer-expr` が `if` / `begin` / `define` / `cond` / `let` / `let*` / `lambda` のみにしか対応しておらず、`case`・名前付き `let` `(let loop (...) ...)`・`letrec` を扱えない。

再帰やクリーネ閉包 `*` を含む PEG インタプリタの第1二村射影（[Issue #950](950-verify-first-futamura-projection-peg-staging-via-mix-against-emit-scheme.md)）を実現する前提条件として、後方ジャンプループを含むインタプリタでの停止性・再帰的残余関数生成を確立する（純粋・一階関数型インタプリタを対象とし、命令型 VM の射影や第2射影はスコープ外とする）。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - [Issue #942](closed/942-connect-specialize-or-widen-in-eval-in-stage-apply-for-futamura-mix.md)（`specialize-or-widen` 接続と第1二村射影実証）
  - [Issue #950](950-verify-first-futamura-projection-peg-staging-via-mix-against-emit-scheme.md)（Direct-Style PEG インタプリタ × `mix` 段階化 — 本 Issue が前提条件）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm) (`eval-in-stage` / `bta-infer-expr` の `case`・名前付き `let`・`letrec` 対応、および `eval-in-stage-apply` / `stage-poly-lower` による自己再帰・残余関数群 `letrec` 生成修正)
- [ ] [test_futamura_projection.scm](../../ulisp/tests/test_futamura_projection.scm) (`JUMP` / `JUMP-IF` 後方ジャンプ付きバイトコードインタプリタの射影テスト、上限超過時 widening 停止テスト、`case`/`let`/`letrec` テスト追加)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/965-futamura-mix-loops-and-case-letrec`

1. `eval-in-stage` と `bta-infer-expr` に `case`（静的対象時の分岐畳み込み＋動的対象時の残余化）、名前付き `let`（`letrec` への脱糖によるループ特殊化対応）、および `letrec`（相互再帰クロージャ環境構築）を追加する。
2. `eval-in-stage-apply` および `stage-poly-lower` を修正し、`body-sv` 内に `target-fn` への自己再帰呼び出しが含まれる場合や循環特殊化が発生した場合に、`spec-memo-residual-fns` に蓄積された特殊化関数定義を残余 `letrec` として包み込み、自己再帰ループが実行可能な残余 Scheme コードへ落ちるようにする。
3. [test_futamura_projection.scm](../../ulisp/tests/test_futamura_projection.scm) に後方ジャンプ（`JUMP` / `JUMP-IF`）を含むループプログラム用バイトコードインタプリタ（例：動的カウンタのループ加算）を追加し、展開爆発せず有限の残余再帰関数へ特殊化されてインタプリタ直接実行と同値の結果を返すことを検証する。詳細手順は `polish-issue` にて精緻化する。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `eval-in-stage` および `bta-infer-expr` が `case`・名前付き `let`・`letrec` を正しく段階化/BTA 推論できること
- [ ] 後方ジャンプ（`JUMP` / `JUMP-IF`）を含むプログラムを射影した際、特殊化上限に溢れることなく停止し、再帰的な残余関数（`letrec`）が生成されること
- [ ] 生成された残余コードの評価結果（ループ実行含む）が元のインタプリタ直接実行結果と完全一致すること
- [ ] `make -C ulisp test_futamura_projection test_stage_poly_lower test_lint_sexpr bootstrap_verify_modular` および品質ゲートが全 PASS すること
