# Issue #454: Scope Sets アルゴリズムによる R7RS 衛生的マクロ展開器 (define-syntax, syntax-rules) の実装

## 1. 概要 (Overview)
ILISP の現在のマクロ機構は、非評価の S 式 AST を受け取り再評価する原始的な `define-macro` である。これはシンプルで軽量な反面、変数の意図しない捕捉（Variable Capture）やシャドウイングの危険があり、R7RS 規格が要求する健全性・衛生性（Hygienic Macro System）を満たしていない。

本 Issue では、現代の Scheme / Racket における最先端の衛生的マクロ理論である **Matthew Flatt (POPL 2016) "Binding as Sets of Scopes"（スコープ集合モデル）** を採用し、ILISP 向けの健全で変数捕捉フリーな衛生的マクロ展開器（`define-syntax`, `syntax-rules`）を実装する。

---

## 2. 目的とゴール (Goals)
1. **Scope Sets（スコープ集合）モデルの基盤実装**:
   - `Scope` オブジェクト（一意な識別子を持つスコープ）
   - 識別子（`SyntaxIdentifier` またはスコープ集合を保持する構文オブジェクト）
   - 構文木とスコープの伝播・付与機構（スコープ追加・削除操作）
2. **`syntax-rules` パターンマッチング＆テンプレート展開エンジンの実装**:
   - パターン記法: リテラル識別子、パターン変数、エリプシス (`...`)
   - 深度付き反復展開（エリプシスによるリスト要素の一括展開）
   - マクロ展開時に新しい一意スコープ（Macro-use Scope）を生成・付与し、マクロ導入変数が呼出側レキシカル変数と絶対に衝突しない衛生性保証
3. **`define-syntax` 特殊形式の評価器・コンパイラ統合**:
   - `evaluator.py`: 評価器における `define-syntax` 束縛の登録と、式展開（Macroexpansion-time）と実行時（Runtime）のフェーズ分離
   - `py_codegen/compiler.py`: Backend A におけるコンパイル時マクロ展開の統合
4. **標準構文マクロの健全化検証**:
   - 既存の `when`, `unless`, `let`, `cond` などのコア構文マクロを `syntax-rules` でテストし、従来の `define-macro` との完全な後方互換・共存を保証

---

## 3. 完了条件 (Definition of Done)
- [x] `ilisp/syntax.py` において Scope Sets アルゴリズムの基礎データ構造（`Scope`, `Syntax`, `PatternBinding`）が実装されている。
- [x] `syntax-rules` によるパターンマッチ（リテラル照合、パターン変数束縛、`...` 反復）とテンプレート置換が正確に動作する。
- [x] 変数捕捉（Capture）が発生しないことが単体テストで厳密に実証されている（例: マクロ内部の局所変数が引数として渡された同名シンボルを捕捉しないこと）。
- [x] `(define-syntax ... (syntax-rules ...))` が Tree-walk 評価器および Backend A コンパイラで動作する。
- [x] `tests/ilisp/test_scope_sets.py` で網羅的なテストが追加され、全テストが 100% PASS すること（全 87 件完全通過）。
- [x] 相対リンクルール、完全日本語、静的解析・型検査（flake8, mypy --strict）を通過すること。

---

## 4. 実装結果サマリー (Implementation Summary)
- **Scope Sets アルゴリズムの実装 (`ilisp/syntax.py`)**:
  - Matthew Flatt (POPL 2016) の "Binding as Sets of Scopes" に基づく `Scope` および `Syntax` オブジェクトを構築。
  - マクロ展開時に一意な Macro-use scope を付与し、マクロ導入シンボルを衛生的に名前空間分離することで変数捕捉（Variable Capture）を完全に防止。
- **`syntax-rules` パターンマッチ & テンプレート展開エンジン**:
  - リテラル照合、パターン変数へのバインディング、および任意深さのエリプシス (`...`) 反復展開を実装。
- **評価器 & コンパイラへの統合**:
  - `evaluator.py`: `define-syntax` 特殊形式および `SyntaxRulesTransformer` 呼出によるトランポリン式 AST 展開。
  - `compiler.py` (Backend A): コンパイル時マクロ展開フェーズ (`_expand_macros`) および `_compile_expr` における `define-syntax` 透過統合。
- **品質・テスト検証**:
  - `tests/ilisp/test_scope_sets.py`: 9 件の専用テスト（古典的スワップマクロにおける変数捕捉防止検証、エリプシス展開、Backend A コンパイル連携等）を追加。
  - ILISP 全 87 件のテストが 100% PASS。
  - `flake8`、`mypy --strict` 0 エラー達成。
