---
ID: 533
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] パターンマッチング型衛生的マクロ展開器 (define-syntax / syntax-rules) のサブセット実装 (ID: 533)

## 1. 概要 / Summary
現在の ULisp は、Common Lisp 由来の非衛生的 S 式変換マクロ（`define-macro` / `defmacro`）のみをサポートしており、複雑な構文糖や DSL を定義する際に一時変数の名前衝突（Variable Capture）が発生するリスクがある。
また、外部の成熟した R7RS ライブラリコードの多くは `define-syntax` と `syntax-rules` を前提として設計されているため、移植性の障壁となっている。
本 Issue では、R7RS Section 4.3（Macros: `syntax-rules`）に準拠したパターンマッチング型衛生的マクロ展開器のサブセット（リテラルリスト、エリプシス `...` パターン反復、およびローカルスコープ名の自動リネーミング）を自前実装し、`ulisp/passes/01_macro_expander.scm` に統合する。

---

## 2. トレーサビリティ / Traceability
- **関連規格**:
  - R7RS Section 4.3 (Derived expression types: `syntax-rules`, `define-syntax`, `let-syntax`)
  - Kohlbecker et al. (LFP 1986): "Hygienic macro expansion"
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第2章 ナノパスコンパイラパイプライン)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連先行 Issue**:
  - Issue #500: メタサーキュラーマクロ展開パスの自己ホスティング統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/01_macro_expander.scm](../../ulisp/passes/01_macro_expander.scm) (`syntax-rules` パターンマッチャおよびテンプレート展開エンジンの実装)
- [ ] [ulisp/lib/syntax.scm](../../ulisp/lib/syntax.scm) (新規作成: `syntax-rules` サポートライブラリ)
- [ ] [ulisp/tests/test_syntax_rules.scm](../../ulisp/tests/test_syntax_rules.scm) (新規作成: 衛生的マクロ単体テスト)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (AOT バイナリ実行検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/533-ulisp-hygienic-syntax-rules-macro-expander`

1. **パターンマッチャ（Pattern Matcher）**:
   - `(syntax-rules (literals ...) (pattern template) ...)` のパターン構文を解析。
   - アンダースコア `_`、ワイルドカード、および可変長反復エリプシス（`...`）のバインド環境抽出。
2. **テンプレート展開器とスコープリネーミング（Renamer）**:
   - マクロ展開時に新しく導入される束縛変数に対し、ユニークな内部識別子（`gensym` またはインデックス付きシンボル）を自動割り当てし、呼出元の自由変数との意図しない衝突を防止。
3. **既存パイプラインとの共存**:
   - トップレベルの `rewrite-top-level` において、`define-syntax` を検出し、マクロ環境テーブルにルールを登録。
   - 従来の `define-macro` も後方互換性のため維持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(define-syntax my-when (syntax-rules () ((_ test body ...) (if test (begin body ...)))))` が正しく定義・展開されること。
- [ ] 変数捕捉（Variable Capture）が発生するテストケースにおいて、呼出元の変数が保護されること。
- [ ] エリプシス `...` による 0 個以上の式列の展開が正確に動作すること。
- [ ] 自己ホスティングコンパイラのビルドおよび全単体テストが完全一致でパスすること。
