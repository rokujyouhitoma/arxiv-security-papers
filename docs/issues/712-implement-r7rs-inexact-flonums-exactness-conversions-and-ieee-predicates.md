---
ID: 712
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.2 不正確実数 (Flonum) と正確性変換 (exact / inexact)・IEEE 特殊値述語の実装 (ID: 712)

## 1. 概要 / Summary
R7RS-small §6.2 の不正確実数 (Inexact Real / Flonum) をボックス化数値型 `<flonum>` として導入し、正確性述語 (`inexact?`, `exact?`, `real?`)、IEEE 特殊値述語 (`finite?`, `infinite?`, `nan?`)、および正確性相互変換手続き (`inexact`, `exact`) を完全実装する。あわせて四則演算・比較演算における正確性伝播則 (Inexactness contagion) を統合し、コンプライアンス表の該当 7 項目を **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.2 (Exactness), §6.2.6 (`inexact?`, `real?`, `finite?`, `infinite?`, `nan?`, `exact`, `inexact`)
  - 先行依存: [Issue #711 (Exact Rationals)](711-implement-r7rs-exact-rationals-rounding-and-rationalize.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [math.scm](../../ulisp/lib/math.scm)
- [ ] [predicates.scm](../../ulisp/lib/predicates.scm)
- [ ] [equality.scm](../../ulisp/lib/equality.scm)
- [ ] [base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [inexact.sld](../../ulisp/lib/scheme/inexact.sld)
- [ ] [test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

