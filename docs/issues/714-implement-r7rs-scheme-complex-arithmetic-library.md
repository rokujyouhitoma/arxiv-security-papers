---
ID: 714
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-small (scheme complex) 複素数算術ライブラリの完全実装 (ID: 714)

## 1. 概要 / Summary
R7RS-small 標準ライブラリ `(scheme complex)` で規定される複素数型 `<complex>` および全 6 手続き (`make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`) ならびに `complex?` 述語と複素数四則演算を実装し、`(scheme complex)` ライブラリの準拠率を **0% (×) → 100% (◎)** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2, §1.4 標準 16 ライブラリ)
  - R7RS-small §6.2.6 (`make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`, `complex?`)
  - 先行依存: [Issue #713 (`(scheme inexact)`)](713-implement-r7rs-scheme-inexact-transcendental-math-library.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [math.scm](../../ulisp/lib/math.scm)
- [ ] [predicates.scm](../../ulisp/lib/predicates.scm)
- [ ] [equality.scm](../../ulisp/lib/equality.scm)
- [ ] [complex.sld](../../ulisp/lib/scheme/complex.sld)
- [ ] [r5rs.sld](../../ulisp/lib/scheme/r5rs.sld)
- [ ] [test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/714-implement-r7rs-scheme-complex-arithmetic-library`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

