---
ID: 825
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] Nanopass AST 定数式評価器 (eval-in-language) およびコンパイル時計算 (CTFE) 基盤の導入 (ID: 825)

## 1. 概要 / Summary
Nanopass の各中間言語定義（`define-language`）に基づく純粋な式ノードを走査し、コンパイル時に直接評価・還元する軽量な AST 評価器フレームワーク（`eval-in-language`）を導入する。
これにより、既存の Scheme コンパイラにおける高度な定数畳み込み（Constant Folding）および部分評価（Partial Evaluation）を促進するとともに、将来の C プリプロセッサ（`#if` 式）やセマンティクス解析（Enum、配列長定数、構造体初期化子）におけるコンパイル時定数評価器（CTFE: Compile-Time Function Execution）の共通基盤を提供する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (A1: 多倍長整数, B1: プリプロセッサ, B4: 意味解析)
- **関連 Issue**: #817 (CP0 Optimization), #824 (Source Span), #832 (Pure Scheme Bignum)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm): 言語文法定義に基づく AST インタプリタ評価フレームワーク
- [ ] [ulisp/compiler/050_cp0.scm](../../ulisp/compiler/050_cp0.scm): 定数式ノードの還元処理との統合
- [ ] [ulisp/tests/test_eval_in_language.scm](../../ulisp/tests/test_eval_in_language.scm): 定数式還元・CTFE 単体テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/825-ast-eval-in-language-ctfe`

1. 中間言語向けの汎用 Tree-walk インタプリタコアの実装：
   - 純粋な算術式、論理演算、条件式、局所バインド（let）を副作用なしで評価する環境管理基盤を定義。
   - 実行ステップ数または再帰深度の上限を設定し、コンパイル時無限ループ（非停止計算）を防止。
2. Nanopass マクロ定義との連携：
   - `(define-evaluator-for-language <lang-name> ...)` による AST タグ別ディスパッチャの自動生成。
3. Scheme の CP0 パスへの組み込み：
   - 定数引数のみからなる純粋関数呼出しを走査時に即時値へ還元。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 中間表現レベルで副作用のない純粋算術・論理式が、コンパイル時に完全に定数ノードへ還元されること。
- [ ] 非停止ループを含む悪意ある式が与えられた場合でも、リミット到達で安全に未還元のままフォールバックすること。
- [ ] 単体テスト `test_eval_in_language.scm` が全ケース合格すること。
