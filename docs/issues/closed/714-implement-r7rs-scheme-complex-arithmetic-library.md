---
ID: 714
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-04
---

# [FEAT/ENH] R7RS-small (scheme complex) 複素数算術ライブラリの完全実装 (ID: 714)

## 1. 概要 / Summary
R7RS-small 標準ライブラリ `(scheme complex)` で規定される複素数型 `<complex>` および全 6 手続き (`make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`) ならびに `complex?` 述語と複素数四則演算を実装し、`(scheme complex)` ライブラリの準拠率を **0% (×) → 100% (◎)** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2, §1.4 標準 16 ライブラリ)
  - R7RS-small §6.2.6 (`make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`, `complex?`)
  - 先行依存: [Issue #713 (`(scheme inexact)`)](713-implement-r7rs-scheme-inexact-transcendental-math-library.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [math.scm](../../../ulisp/lib/math.scm)
- [x] [predicates.scm](../../../ulisp/lib/predicates.scm)
- [x] [equality.scm](../../../ulisp/lib/equality.scm)
- [x] [complex.sld](../../../ulisp/lib/scheme/complex.sld)
- [x] [r5rs.sld](../../../ulisp/lib/scheme/r5rs.sld)
- [x] [test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/714-implement-r7rs-scheme-complex-arithmetic-library`

1. **ボックス化複素数表現 `<complex>` と生成手続き ([math.scm](../../../ulisp/lib/math.scm), [predicates.scm](../../../ulisp/lib/predicates.scm))**:
   - `#(ulisp-complex-tag <real-part> <imag-part>)` として表現する。
   - `(make-rectangular x1 x2)`: `x2` が正確ゼロ (`0`) の場合は実数 `x1` に自動降格 (demote) し、それ以外は `#(ulisp-complex-tag x1 x2)` を返す。
   - `(make-polar r theta)`: $x_1 = r \cos\theta$, $x_2 = r \sin\theta$ により直交座標へ変換して構築する (`theta = 0` で正確ゼロなら `r` をそのまま返す)。
2. **複素数アクセサおよび極座標計算 (`real-part`, `imag-part`, `magnitude`, `angle`) ([math.scm](../../../ulisp/lib/math.scm))**:
   - `(real-part z)`: 実数に対しては `z` 自身、`<compnum>` に対しては `(vector-ref z 1)` を返す。
   - `(imag-part z)`: 実数に対しては `0`、`<compnum>` に対しては `(vector-ref z 2)` を返す。
   - `(magnitude z)`: 実数に対しては絶対値、`<compnum>` に対しては $\sqrt{x_1^2 + x_2^2}$（ピタゴラス三つ組等の完全平方な正確数は正確値を保持）を返す。
   - `(angle z)`: `(atan (imag-part z) (real-part z))` により偏角 $[-\pi, \pi]$ を返す。
3. **複素数四則演算 (`comp+`, `comp-`, `comp*`, `comp/`, `comp=`) と `num+` / `num-` / `num*` / `num/` / `num=` 統合 ([math.scm](../../../ulisp/lib/math.scm))**:
   - `(a+bi) + (c+di) = (a+c) + (b+d)i`
   - `(a+bi) - (c+di) = (a-c) + (b-d)i`
   - `(a+bi) * (c+di) = (ac - bd) + (ad + bc)i`
   - `(a+bi) / (c+di) = ((ac + bd)/(c^2 + d^2)) + ((bc - ad)/(c^2 + d^2))i`

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `make-rectangular`, `make-polar`, `real-part`, `imag-part`, `magnitude`, `angle`, `complex?` および複素数四則演算が実装され、[test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) が PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability test_numeric_tower` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) の該当項目および `(scheme complex)` が **◎** に更新されていること。

