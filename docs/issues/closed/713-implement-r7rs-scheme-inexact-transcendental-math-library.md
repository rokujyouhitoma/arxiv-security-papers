---
ID: 713
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-04
---

# [FEAT/ENH] R7RS-small (scheme inexact) 初等超越関数・平方根ライブラリの完全実装 (ID: 713)

## 1. 概要 / Summary
R7RS-small 標準ライブラリ `(scheme inexact)` で規定される初等超越関数および平方根手続き (`sqrt`, `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`) を、外部 C ライブラリ (`libm`) に依存しない純粋な ULisp AOT ネイティブアルゴリズム（Newton-Raphson 法、範囲縮小 + Taylor/Padé 近似）で完全実装し、`(scheme inexact)` ライブラリの準拠率を **0% (×) → 100% (◎)** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2, §1.4 標準 16 ライブラリ)
  - R7RS-small §6.2.6 (`exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`)
  - 先行依存: [Issue #712 (Inexact Flonums)](712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [math.scm](../../../ulisp/lib/math.scm)
- [x] [inexact.sld](../../../ulisp/lib/scheme/inexact.sld)
- [x] [r5rs.sld](../../../ulisp/lib/scheme/r5rs.sld)
- [x] [test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/713-implement-r7rs-scheme-inexact-transcendental-math-library`

1. **`sqrt` (平方根) ([math.scm](../../../ulisp/lib/math.scm))**:
   - 完全平方な正確整数・正確有理数（例: `(sqrt 9) => 3`, `(sqrt 9/16) => 3/4`）は `exact-integer-sqrt` を用いて正確な結果を返す。
   - 非完全平方な正実数に対しては $10^6$ スケール固定小数点（または `exact-integer-sqrt` の $10^{12}$ スケール計算）により高精度な `<flonum>` を返す。
   - 負の実数 $x < 0$ に対しては純虚数 `#(ulisp-complex-tag 0 (sqrt (- x)))` を返し、R7RS §6.2.6 の複素平方根仕様にも準拠する。
2. **指数・対数関数 (`exp`, `log`) ([math.scm](../../../ulisp/lib/math.scm))**:
   - `(exp x)`: $x = k \ln 2 + r$ ($|r| \le \frac{1}{2}\ln 2$) に範囲縮小し、Taylor 級数展開 $\sum_{n=0}^{8} r^n / n!$ と $2^k$ スケーリングで算出する。
   - `(log x)` および 2 引数 `(log x base)` (R7RS §6.2.6): $x = 2^k \cdot m$ に正規化し、$\ln m = 2 \sum_{j=0}^{6} \frac{1}{2j+1} \left(\frac{m-1}{m+1}\right)^{2j+1}$ (artanh 級数) により高速収束計算する。2 引数の場合は `(/ (log x) (log base))` を返す。
3. **三角関数・逆三角関数 (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`) ([math.scm](../../../ulisp/lib/math.scm))**:
   - `(sin x)`, `(cos x)`, `(tan x)`: $[-\pi, \pi]$ および $[0, \pi/4]$ への対称・余角範囲縮小と Taylor 多項式により算出する。
   - `(atan y)` および 2 引数象限認識 `(atan y x)` (`atan2`): $|t| \le 1$ への折り返しと半角変換 $t \mapsto \frac{t}{1 + \sqrt{1+t^2}}$ を2回適用し、Taylor 展開で高精度算出する。
   - `(asin x)`, `(acos x)`: $\arcsin(x) = \text{atan2}(x, \sqrt{1 - x^2})$, $\arccos(x) = \text{atan2}(\sqrt{1 - x^2}, x)$ により特異点 ($\pm 1$) まで安定に算出する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `sqrt`, `exp`, `log` (1/2引数), `sin`, `cos`, `tan`, `asin`, `acos`, `atan` (1/2引数) が実装され、[test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) が PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability test_numeric_tower` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) の該当項目および `(scheme inexact)` が **◎** に更新されていること。

