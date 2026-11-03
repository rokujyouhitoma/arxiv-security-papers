---
ID: 713
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small (scheme inexact) 初等超越関数・平方根ライブラリの完全実装 (ID: 713)

## 1. 概要 / Summary
R7RS-small 標準ライブラリ `(scheme inexact)` で規定される初等超越関数および平方根手続き (`sqrt`, `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`) を、外部 C ライブラリ (`libm`) に依存しない純粋な ULisp AOT ネイティブアルゴリズム（Newton-Raphson 法、範囲縮小 + Taylor/Padé 近似）で完全実装し、`(scheme inexact)` ライブラリの準拠率を **0% (×) → 100% (◎)** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2, §1.4 標準 16 ライブラリ)
  - R7RS-small §6.2.6 (`exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`)
  - 先行依存: [Issue #712 (Inexact Flonums)](712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [math.scm](../../ulisp/lib/math.scm)
- [ ] [inexact.sld](../../ulisp/lib/scheme/inexact.sld)
- [ ] [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)
- [ ] [test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/713-implement-r7rs-scheme-inexact-transcendental-math-library`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

