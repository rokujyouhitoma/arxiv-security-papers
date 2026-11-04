---
ID: 712
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-04
---

# [FEAT/ENH] R7RS §6.2 不正確実数 (Flonum) と正確性変換 (exact / inexact)・IEEE 特殊値述語の実装 (ID: 712)

## 1. 概要 / Summary
R7RS-small §6.2 の不正確実数 (Inexact Real / Flonum) をボックス化数値型 `<flonum>` として導入し、正確性述語 (`inexact?`, `exact?`, `real?`)、IEEE 特殊値述語 (`finite?`, `infinite?`, `nan?`)、および正確性相互変換手続き (`inexact`, `exact`) を完全実装する。あわせて四則演算・比較演算における正確性伝播則 (Inexactness contagion) を統合し、コンプライアンス表の該当 7 項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.2 (Exactness), §6.2.6 (`inexact?`, `real?`, `finite?`, `infinite?`, `nan?`, `exact`, `inexact`)
  - 先行依存: [Issue #711 (Exact Rationals)](711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [math.scm](../../../ulisp/lib/math.scm)
- [x] [predicates.scm](../../../ulisp/lib/predicates.scm)
- [x] [equality.scm](../../../ulisp/lib/equality.scm)
- [x] [base.sld](../../../ulisp/lib/scheme/base.sld)
- [x] [inexact.sld](../../../ulisp/lib/scheme/inexact.sld)
- [x] [test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates`

1. **ボックス化不正確実数 `<flonum>` と IEEE 特殊値の表現 ([predicates.scm](../../../ulisp/lib/predicates.scm), [math.scm](../../../ulisp/lib/math.scm))**:
   - `#(ulisp-flonum-tag <val>)` として表現する。有限値は $10^6$ スケール（マイクロ単位固定小数点 62-bit 整数）として保持し、特殊値は `'pos-inf` (`+inf.0`), `'neg-inf` (`-inf.0`), `'nan` (`+nan.0`) シンボルで保持する。
   - コンストラクタ `make-flonum`, `make-flonum-micros`, 定数 `+inf.0`, `-inf.0`, `+nan.0` を定義する。
2. **IEEE 754 特殊値述語 (`finite?`, `infinite?`, `nan?`) ([predicates.scm](../../../ulisp/lib/predicates.scm))**:
   - `finite?`: Fixnum, `<ratnum>`, 有限 `<flonum>`、および両成分が有限の `<complex>` に対して `#t`、無限大・NaN を含む場合は `#f`。
   - `infinite?`: `+inf.0` / `-inf.0` またはいずれかの成分が無限大の `<complex>` に対して `#t`。
   - `nan?`: `+nan.0` またはいずれかの成分が NaN の `<complex>` に対して `#t`。
3. **正確性変換 (`inexact`, `exact`, `exact->inexact`, `inexact->exact`) ([math.scm](../../../ulisp/lib/math.scm))**:
   - `(inexact z)`: Fixnum `n` を `#(ulisp-flonum-tag (* n 1000000))` に、`<ratnum n/d>` を `#(ulisp-flonum-tag (round-quotient (* n 1000000) d))` に変換する。既に不正確な場合はそのまま返す。
   - `(exact z)`: 有限 `<flonum v>` を `(make-rational v 1000000)` に変換する（整数値は Fixnum に自動降格）。無限大・NaN に対してはエラーを送出する。
4. **Flonum 算術・比較と不正確性伝播 (`flo+`, `flo-`, `flo*`, `flo/`, `flo=`, `flo<`, `flo<=`, `flo>`, `flo>=`) ([math.scm](../../../ulisp/lib/math.scm))**:
   - 混合型（Fixnum / `<ratnum>` / `<flonum>`）を受け取り、いずれかが不正確であれば結果も `<flonum>` として返す不正確性伝播 (Inexactness contagion) を実装する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `<flonum>`, `inexact`, `exact`, `finite?`, `infinite?`, `nan?`, `inexact?`, `real?` が実装され、[test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) が PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability test_numeric_tower` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) の該当項目が **◎** に更新されていること。

