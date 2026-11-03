---
ID: 711
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.2 正確有理数 (Exact Rationals) と丸め手続き・rationalize の実装 (ID: 711)

## 1. 概要 / Summary
ULisp の 62-bit Fixnum 高速パスを維持しつつ、R7RS-small §6.2 の正確有理数 (Exact Rationals `p/q`) をボックス化ヒープオブジェクト `<ratnum>` として実装する。あわせて `numerator`, `denominator`、有理数対応の丸め手続き (`floor`, `ceiling`, `truncate`, `round` — 最近接偶数丸め)、および最簡有理数近似手続き `rationalize` を完全実装し、コンプライアンス表の該当 8 項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.1 (Numerical types), §6.2.6 (Numerical operations: `rational?`, `numerator`, `denominator`, `floor`, `ceiling`, `truncate`, `round`, `rationalize`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [math.scm](../../ulisp/lib/math.scm)
- [ ] [predicates.scm](../../ulisp/lib/predicates.scm)
- [ ] [equality.scm](../../ulisp/lib/equality.scm)
- [ ] [base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/711-implement-r7rs-exact-rationals-rounding-and-rationalize`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

