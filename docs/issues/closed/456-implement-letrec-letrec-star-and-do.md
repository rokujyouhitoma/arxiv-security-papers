# Issue #456: R7RS コア構文の完全網羅 (letrec, letrec*, do) の実装

## 1. 概要 (Overview)
ILISP はこれまでに `quote`, `lambda`, `if`, `set!`, `begin`, `define`, `cond`, `case`, `and`, `or`, `when`, `unless`, `let`, `let*`, `let-values`, `let*-values`, `quasiquote`, `define-syntax` などの主要コア構文を実装してきた。
R7RS-small 仕様の第 4 章（Expressions）において残されたコア構文は、相互再帰束縛 `letrec`, `letrec*` および構造化反復構文 `do` である。

本 Issue では、これら 3 つの必須コア構文を実装・テストし、ILISP における R7RS-small コア式・構文（Section 4）の仕様準拠率を **100% 完全準拠** に到達させる。

---

## 2. 目的とゴール (Goals)
1. **`letrec` 構文の実装**:
   - `(letrec ((var val) ...) body ...)` の脱糖マクロ
   - 一時変数を介した代入パターンにより、相互再帰関数（例: `is-even?` と `is-odd?`）の定義を可能にする
2. **`letrec*` 構文の実装**:
   - `(letrec* ((var val) ...) body ...)` の逐次代入脱糖マクロ
   - 後続の `val` 評価時点で先行する `var` の値が確定・参照可能となるセマンティクスを保証
3. **`do` 構造化反復構文の実装**:
   - `(do ((<var> <init> [<step>]) ...) (<test> [<expr> ...]) <command> ...)`
   - ループ初期化、各イテレーションでのステップ更新、終了条件判定および結果式返却のループ脱糖
4. **Tree-walk 評価器 & Backend A (Python AST コンパイラ) への統合**:
   - `stdlib/base.ilisp` へのマクロ定義追加と、コンパイラ展開・自己 TCO 最適化との親和性確保
5. **テストスイートの整備**:
   - 相互再帰クロージャ呼び出し、逐次束縛参照、フィボナッチ/階乗ループ等の `do` 反復の検証

---

## 3. 完了条件 (Definition of Done)
- [x] `stdlib/base.ilisp` に `letrec`, `letrec*`, `do` および Named let が定義されている。
- [x] `letrec` による相互再帰関数（`is-even?` / `is-odd?`）が正常に実行できる。
- [x] `letrec*` による先行束縛変数の逐次参照が正常に動作する。
- [x] `do` 反復構文（ステップ式省略対応、副作用コマンド実行、終了後結果式返却）が正確に動作する。
- [x] Tree-walk 評価器と Backend A コンパイラの両方で動作が保証されている。
- [x] `tests/ilisp/test_core_syntax.py` に単体テストが追加され、全テストが 100% PASS すること（全 105 件完全通過）。
- [x] 静的解析（flake8, mypy --strict）をパスし、ドキュメントの R7RS コア構文ステータスを更新すること。

---

## 4. 実装結果サマリー (Implementation Summary)
- **相互再帰局所束縛 (`letrec`, `letrec*`) の実装**:
  - `_ilisp_make_undef_bindings` により一時的に未定義セル（`'()`）を確保し、`set!` 式列によって相互再帰関数クロージャをバインドする脱糖マクロを構築。
  - `letrec*` における逐次代入セマンティクスを保証。
- **構造化反復構文 (`do`) の実装**:
  - 各変数節の初期化式、ステップ式（省略時は現変数保持）、終了判定テスト式、終了時返却式、および各イテレーションでの副作用コマンド列を `letrec` ループに脱糖展開。
- **名前付き `let` (Named let) のサポート**:
  - `(let name ((var val) ...) body ...)` を `letrec` 再帰呼出に脱糖する拡張を `let` マクロに導入。
- **品質・テスト検証**:
  - `tests/ilisp/test_core_syntax.py`: 9 件の単体テストを追加。
  - ILISP テストスイート **全 105 件が 100% PASS**。
  - R7RS 特殊形式・コア構文カテゴリの準拠率を **94% (17/18)** へ向上。
