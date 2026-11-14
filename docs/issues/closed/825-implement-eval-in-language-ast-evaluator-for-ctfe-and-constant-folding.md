---
ID: 825
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] Nanopass AST 定数式評価器 (eval-in-language) およびコンパイル時計算 (CTFE) 基盤の導入 (ID: 825)

## 1. 概要 / Summary
Nanopass の中間言語定義（`define-language`）に基づく純粋な AST ノードを走査し、コンパイル時に直接評価・還元する軽量な AST 評価器フレームワーク（`eval-in-language`）を導入する。
本機能により、既存の CP0 最適化パス（`050_cp0.scm`）における多段定数畳み込み（Constant Folding）および部分評価（Partial Evaluation）を飛躍的に強化するとともに、将来の C プリプロセッサ（`#if` 定数式）やセマンティクス解析（Enum 定数、配列長定数、静的構造体初期化子）で不可欠となるコンパイル時定数評価器（CTFE: Compile-Time Function Execution）の統一基盤を提供する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**: §2 (A1: 多倍長整数, B1: Cプリプロセッサ式評価, B4: 意味解析型サイズ計算)
- **DSN-33 仕様書**: §3.1 (Nanopass コンパイラアーキテクチャ)
- **関連 Issue**:
  - #817: CP0 最適化 Nanopass の多重適用と収束制御
  - #824: Nanopass AST の First-Class Source Span & メタデータ保持機構
  - #832: Pure Scheme 任意精度多倍長整数（Bignum）演算ライブラリの自立実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/eval_in_language.scm](../../../ulisp/compiler/eval_in_language.scm): 言語文法定義に基づく AST インタプリタ評価フレームワーク（新規作成）
- [x] [ulisp/compiler/primitives.scm](../../../ulisp/compiler/primitives.scm): 純粋関数（pure-prim?）判定テーブルの拡充
- [x] [ulisp/frontend/050_cp0.scm](../../../ulisp/frontend/050_cp0.scm): CP0 パスでの `eval-in-language` 統合および定数式還元の強化
- [x] [ulisp/Makefile](../../../ulisp/Makefile): `eval_in_language.scm` のビルド・テストターゲット追加
- [x] [ulisp/tests/test_eval_in_language.scm](../../../ulisp/tests/test_eval_in_language.scm): 定数式還元・CTFE・燃料消費上限・例外フォールバックの単体テスト（新規作成）

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-400 (Uncontrolled Resource Consumption / CPU & Memory DoS)**:
  - 悪意あるコードまたは誤った再帰定義（例: `(letrec ((f (lambda () (f)))) (f))`）がコンパイル時計算に渡された場合、コンパイラが無限ループまたはスタックオーバーフローでハングするリスク。
  - **対策**: 各評価ステップごとにデクリメントされる明示的な燃料カウンタ（`*ctfe-step-limit*`、デフォルト 10,000 ステップ）および再帰深度カウンタ（`*ctfe-max-depth*`、デフォルト 256 レベル）を導入。上限到達時は例外を捕捉し、即座に安全な未還元 AST ノードとしてフォールバックする。
- **CWE-843 (Type Confusion / AST Corruption)**:
  - 評価結果が中間言語（L_core / L_anf 等）の文法定義に適合しない不正な形式で AST に混入するリスク。
  - **対策**: 還元値は必ず `val->ast-const` を経由して中間言語の正規定数ノード（`'const` / リテラル）へと安全にデシュガーし、Nanopass Verifier に合格することを保証する。
- **副作用分離 (Purity Enforcement)**:
  - コンパイル時評価では I/O 操作（`display`, `read`）、大域状態の破壊的代入（`set!`）、アロケーション副作用、未定義システムコールの実行を厳格に禁止する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/825-ast-eval-in-language-ctfe`

### ステップ 1: `eval-in-language.scm` のコアアーキテクチャ設計・実装
1. **評価環境（Environment）モデル**:
   - `(ctfe-env-empty)`: 空の環境。
   - `(ctfe-env-extend env sym val)`: 変数束縛の追加。
   - `(ctfe-env-lookup env sym)`: 変数値の探索（未束縛時は未還元シンボルを返す）。
2. **燃料管理（Fuel & Budgeting）機構**:
   - `*ctfe-default-step-limit*`: デフォルト 10,000。
   - `*ctfe-default-depth-limit*`: デフォルト 256。
   - カウンタが尽きた場合は、特殊な停止トークン `(%ctfe-timeout <original-expr>)` を返し、元の式をそのまま温存。
3. **DSL マクロ `(define-evaluator-for-language <lang-name> ...)` の実装**:
   - Nanopass 中間言語ごとに、有効なタグ（`const`, `if`, `begin`, `let`, `letrec`, `call` 等）に応じた再帰的 Tree-walk 評価手続きを構築。
   - 式が純粋（`pure-expr?`）かつ引数が全て確定値である場合のみ評価を進行。

### ステップ 2: 純粋関数・プリミティブの評価ハンドラ登録
1. 算術演算: `+`, `-`, `*`, `quotient`, `modulo`, `remainder`, `abs`, `min`, `max`, `fx+`, `fx-`, `fx*`
2. ビット演算: `bitwise-and`, `bitwise-ior`, `bitwise-xor`, `bitwise-not`, `arithmetic-shift`
3. 論理演算・述語: `not`, `boolean?`, `number?`, `null?`, `pair?`, `symbol?`, `char?`, `string?`, `=`, `<`, `<=`, `>`, `>=`, `eq?`, `eqv?`, `equal?`
4. リスト・タプル操作（純粋な読み取り・構築）: `cons`, `car`, `cdr`, `caar`, `cadr`, `cdar`, `cddr`, `list`, `length`, `append`

### ステップ 3: `050_cp0.scm` への CTFE 統合
1. `rule-cp0-const-fold` を拡張し、従来の 1〜2 引数の単発 `fold-const-op` に加え、ネストした式や局所バインディングを含む式に対して `(eval-in-language 'L_core expr)` を試行。
2. 評価に成功し、結果が定数値となった場合は AST ノードを直ちに置換。未解決の自由変数が含まれる場合やタイムアウト時は、元の式を保持。

### ステップ 4: 単体テスト `test_eval_in_language.scm` の構築
1. **基本定数式**: `(+ (* 2 3) (- 10 4))` -> `12`
2. **局所束縛**: `(let ((x 10) (y 20)) (+ x y))` -> `30`
3. **条件分岐**: `(if (< 5 10) (* 3 4) (/ 1 0))` -> `12` （デッド分岐の未評価保証）
4. **ネストした純粋関数呼び出し**: 階乗やフィボナッチの定数計算がコンパイル時に完了すること。
5. **リソース上限ガード**: 無限再帰ループ `(letrec ((f (lambda (n) (f (+ n 1))))) (f 0))` がタイムアウトし、コンパイルエラーにならず元の式のままフォールバックすること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/compiler/eval_in_language.scm` が実装され、`define-evaluator-for-language` および `eval-in-language` API が提供されていること。
- [x] 燃料カウンタ・再帰深度リミットによる DoS 防止機構（CWE-400 対策）が動作し、無限ループ式が安全にフォールバックすること。
- [x] `050_cp0.scm` に統合され、ネストした純粋算術・論理・let 式がコンパイル時に定数ノードへ還元されること。
- [x] `make -C ulisp test_eval_in_language` が新規作成され、全テストケースに PASS すること。
- [x] `make -C ulisp verify_zero_gauche` および `make -C ulisp lint_sexpr` が PASS すること。
- [x] 既存の全テストスイートおよびブートストラップ検証（`test_pure_bootstrap.sh`）にリグレッションがないこと。
