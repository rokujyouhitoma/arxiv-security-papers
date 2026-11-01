---
ID: 647
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §4.3.3 マクロ構文エラー報告構文 (syntax-error) の実装 (ID: 647)

## 1. 概要 / Summary
R7RS-small §4.3.3 で規定されている `(syntax-error <message> <args> ...)` 構文を ULisp に実装する。
マクロ展開器（Pass 020: `020_macro_expander.scm`）において、ユーザー定義の `syntax-rules` 内で不正な構文パターンがマッチした際、コンパイル時エラーとして明示的かつ親切なエラーメッセージ・関連引数を送出できるようにする。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 4.3.3 (Syntax-error)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.1
- 関連コンパイラパス: [020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm)
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [tests/test_macro.scm](../../ulisp/tests/test_macro.scm) (新規または追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/647-implement-r7rs-syntax-error-syntax`

1. Pass 020 (`020_macro_expander.scm`) において、`(syntax-error msg args ...)` 形式のフォームがトップレベルまたはマクロ展開中に現れた場合、コンパイルを中断しソース位置・メッセージを出力するハンドラを追加する。
2. `(scheme base)` のエクスポートシンボルに `syntax-error` を追加する。
3. `ref_r7rs_compliance.md` の §4.3.3 のステータスを `◎` に更新する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(syntax-error ...)` を含むマクロ展開が適切な診断メッセージとともにコンパイル時エラーになること。
- [ ] `make test` および CI テストスイートが 100% パスすること。
- [ ] `ref_r7rs_compliance.md` にトレーサビリティが反映されること。

