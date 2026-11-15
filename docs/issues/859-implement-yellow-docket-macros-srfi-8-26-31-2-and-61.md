---
ID: 859
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Yellow Docket 構文拡張マクロ (SRFI 8, 26, 31, 2, 61) の脱糖実装 (ID: 859)

## 1. 概要 / Summary
R7RS 仕様準拠状況リファレンスにおいて「Pass 030 / Pass 020 で完全動作 (◎)」と誤記されていた Yellow Docket および基盤構文マクロ群（SRFI 8 `receive`, SRFI 26 `cut`/`cute`, SRFI 31 `rec`, SRFI 2 `and-let*`, SRFI 61 一般化 `cond`）について、実際にはコンパイラ内に脱糖コードが存在しない。
本 Issue では、これら 5 つの主要構文マクロを Pass 020 (マクロ展開) または Pass 027/028/030 (構文脱糖) に正式実装し、規格への実質的準拠を達成する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Yellow Docket
  - SRFI 8 (RECEIVE), SRFI 26 (CUT/CUTE), SRFI 31 (REC), SRFI 2 (AND-LET*), SRFI 61 (General cond clause)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.3, §2.5
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm)
- [ ] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm)
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/tests/test_yellow_docket_macros.scm](../../ulisp/tests/test_yellow_docket_macros.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/859-implement-yellow-docket-macros-srfi-8-26-31-2-and-61`

1. **SRFI 8 `receive`**:
   - `(receive <formals> <expression> <body> ...)` を `(call-with-values (lambda () <expression>) (lambda <formals> <body> ...))` へ脱糖。
2. **SRFI 31 `rec`**:
   - `(rec (<var> <formals> ...) <body> ...)` -> `(letrec ((<var> (lambda (<formals> ...) <body> ...))) <var>)`
   - `(rec <var> <expr>)` -> `(letrec ((<var> <expr>)) <var>)`
3. **SRFI 2 `and-let*`**:
   - 束縛式、真偽判定、本体評価の短絡連鎖へ再帰的に脱糖。
4. **SRFI 26 `cut` / `cute`**:
   - スロット `<>` およびレストスロット `<...>` を検出し、ラムダ式へ展開。`cute` では固定スロット引数の即時事前評価用の一時束縛 `let` を生成。
5. **SRFI 61 `cond` 拡張**:
   - `(<generator> <guard> => <receiver>)` 形式を検出し、多値受け取りとガード述語検査、レシーバー適用へ脱糖。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `receive`, `rec`, `and-let*`, `cut`, `cute`, SRFI 61 `cond` が Scheme ソース内で正しく機能すること。
- [ ] 新規テストスイート `test_yellow_docket_macros.scm` が全 PASS すること。
- [ ] `ref_r7rs_compliance.md` の記述が真実の実装と完全に整合すること。
