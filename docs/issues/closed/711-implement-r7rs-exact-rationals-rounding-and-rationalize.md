---
ID: 711
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-04
---

# [FEAT/ENH] R7RS §6.2 正確有理数 (Exact Rationals) と丸め手続き・rationalize の実装 (ID: 711)

## 1. 概要 / Summary
ULisp の 62-bit Fixnum 高速パスを維持しつつ、R7RS-small §6.2 の正確有理数 (Exact Rationals `p/q`) をボックス化ヒープオブジェクト `<ratnum>` として実装する。あわせて `numerator`, `denominator`、有理数対応の丸め手続き (`floor`, `ceiling`, `truncate`, `round` — 最近接偶数丸め)、および最簡有理数近似手続き `rationalize` を完全実装し、コンプライアンス表の該当 8 項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.1 (Numerical types), §6.2.6 (Numerical operations: `rational?`, `numerator`, `denominator`, `floor`, `ceiling`, `truncate`, `round`, `rationalize`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [math.scm](../../../ulisp/lib/math.scm)
- [x] [predicates.scm](../../../ulisp/lib/predicates.scm)
- [x] [equality.scm](../../../ulisp/lib/equality.scm)
- [x] [base.sld](../../../ulisp/lib/scheme/base.sld)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) (新規)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/711-implement-r7rs-exact-rationals-rounding-and-rationalize`

1. **ボックス化有理数表現 `<ratnum>` と正規化 ([predicates.scm](../../../ulisp/lib/predicates.scm), [math.scm](../../../ulisp/lib/math.scm))**:
   - `#(ulisp-ratnum-tag <num> <den>)` として表現（`den > 1`, `gcd(|num|, den) = 1`）。
   - `make-rational` において `gcd-2` で約分し、`den < 0` の場合は符号を分子に移し、`den = 1` の場合は即値 Fixnum に自動降格 (demote) する。
   - 有理数四則・比較手続き (`rat+`, `rat-`, `rat*`, `rat/`, `rat=`, `rat<`, `rat<=`, `rat>`, `rat>=`) を提供する。
2. **R7RS §6.2.6 有理数アクセサ・丸め手続き・`rationalize` ([math.scm](../../../ulisp/lib/math.scm))**:
   - `numerator`, `denominator`: Fixnum に対して `n` と `1`、`<ratnum>` に対して既約分子・分母を返す。
   - `floor`, `ceiling`, `truncate`, `round`: Fixnum および `<ratnum>` に対して SRFI 141 の `floor-quotient`, `ceiling-quotient`, `truncate-quotient`, `round-quotient`（最近接偶数丸め）を用いて正確な整数を返す。
   - `rationalize`: 連分数展開アルゴリズムにより $[x - |y|, x + |y|]$ 内の最簡有理数を返す。
3. **述語・等価性・エクスポート更新 ([predicates.scm](../../../ulisp/lib/predicates.scm), [equality.scm](../../../ulisp/lib/equality.scm), [base.sld](../../../ulisp/lib/scheme/base.sld))**:
   - `number?`, `complex?`, `real?`, `rational?`, `exact?` が `<ratnum>` に対して `#t` を返し、`eqv?` / `equal?` が `<ratnum>` の値等価性を判定するように拡張する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `<ratnum>`, `make-rational`, `numerator`, `denominator`, `floor`, `ceiling`, `truncate`, `round`, `rationalize` が実装され、[test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) が PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) の該当 8 項目が **◎** に更新されていること。

