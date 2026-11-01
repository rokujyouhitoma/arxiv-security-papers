---
ID: 647
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS §4.3.3 マクロ構文エラー報告構文 (syntax-error) の実装 (ID: 647)

## 1. 概要 / Summary
R7RS-small §4.3.3 で規定されている `(syntax-error <message> <args> ...)` 構文を ULisp コンパイラおよび標準ライブラリに実装する。
マクロ展開器（Pass 020: `020_macro_expander.scm`）および構文脱糖器（Pass 030: `030_desugar.scm`）において、ユーザー定義の `syntax-rules` マクロ内で不正な構文パターンがマッチした際、コンパイル時・展開時エラーとして明示的かつ詳細なエラーメッセージおよび irritants（関連引数）を送出し、安全にコンパイルを中断できるようにする。

---

## 2. トレーサビリティ / Traceability
- **R7RS-small Specification**: Section 4.3.3 (Syntax-error)
- **関連 Issue**: Issue #533 (syntax-rules マクロ展開器の確立), Issue #562 ((scheme base) ライブラリ定義)
- **仕様リファレンス**: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1 (§4.3.3), §1.4 (`(scheme base)`)
- **関連コンパイラパス**:
  - [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm)
  - [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
  - [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm) (コアキーワード登録および展開時 syntax-error 検知・送出)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) (直接記述された syntax-error のコンパイル時トラップ)
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld) (`syntax-error` のエクスポート宣言)
- [ ] [ulisp/tests/passes/test_020_macro_expander.scm](../../ulisp/tests/passes/test_020_macro_expander.scm) (Pass 020 単体テスト)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (仕様準拠表の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/647-implement-r7rs-syntax-error-syntax`

### 4.1 Pass 020 (`020_macro_expander.scm`) の改修
1. **コア予約語リストへの追加**:
   - `core-form-or-primitive?` に `syntax-error` を追加。
   - 目的: 衛生的マクロ展開において `syntax-error` シンボルが `__hyg_syntax-error_N` に意図せず名前変更されるのを防ぐ。
2. **展開時 syntax-error のインターセプト**:
   - `macro-expand-all` において、展開結果が `(syntax-error <msg> <args> ...)` である場合を判定。
   - メッセージ部 `<msg>`（通常は文字列）と後続の `<args> ...`（データ・S式）を取り出し、ULisp のコンパイル時エラーハンドラ（`error`）を呼び出してコンパイルを中断。
   - エラー形式例: `(apply error (cons (string-append "syntax-error: " (if (string? msg) msg "invalid syntax")) args))`。

### 4.2 Pass 030 (`030_desugar.scm`) の改修
1. マクロ展開を経ずにトップレベルや式中に直接記述された `(syntax-error msg args ...)` についても、実行時コードへ漏れ出さないよう、Pass 030 構文解析・脱糖の段階で検知してコンパイル時エラーとする。

### 4.3 `(scheme base)` ライブラリ定義への追加
1. `ulisp/lib/scheme/base.sld` の `export` リストに `syntax-error` を追加し、R7RS-small 仕様に完全適合させる。

### 4.4 テストと仕様ドキュメントの更新
1. `ulisp/tests/passes/test_020_macro_expander.scm` に、`syntax-rules` 内で `syntax-error` を送出するマクロ（例: パターン不一致時のフォールバック節）を定義し、期待通りコンパイルエラーが発生してメッセージと引数が渡されることを検証する。
2. `ulisp/docs/ref_r7rs_compliance.md` の §4.3.3 `syntax-error` のステータスを `×` から `◎` に更新する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(syntax-error message irritants ...)` がマクロ展開時またはコンパイル時に捕捉され、適切な診断メッセージでエラー終了すること。
- [x] `syntax-rules` のテンプレート内で `syntax-error` が hygienic リネームされずに正しく機能すること。
- [x] `(scheme base)` から `syntax-error` がエクスポートされること。
- [x] `tests/passes/test_020_macro_expander.scm` に単体テストが追加され、`./ulisp/test.sh` が 100% PASS すること。
- [x] `ulisp/docs/ref_r7rs_compliance.md` のステータスが `◎` に更新され、Issue #647 へのトレーサビリティリンクが記載されていること。
