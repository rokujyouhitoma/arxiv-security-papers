---
ID: 558
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] R7RS 基本整数算術手続き (square / gcd / lcm / expt / remainder) の実装 (ID: 558)

## 1. 概要 / Summary
R7RS 6.2.6 (Numerical operations) に規定されている基本算術・整数論的手続きである `square`, `gcd`, `lcm`, `expt`, `remainder` (および `modulo`) を標準ライブラリに実装する。
ULisp の整数算術プリミティブ (`+`, `-`, `*`, `/`, `<`, `=`, `abs` など) をベースに、ユークリッドの互除法や繰り返し二乗法 (Binary Exponentiation) を用いた高速かつ安全なアルゴリズムを Pure Scheme で提供し、数値計算・暗号プロトコル・ハッシュ計算の基盤を強化する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 6.2.6 (Numerical operations)
  - `(square z)`: `(* z z)` を計算。
  - `(gcd n1 ...)`: 最大公約数（Greatest Common Divisor）を計算。引数なしは 0。
  - `(lcm n1 ...)`: 最小公倍数（Least Common Multiple）を計算。引数なしは 1。
  - `(expt z1 z2)`: 累乗 `z1^z2` を計算。
  - `(remainder n1 n2)`: 整数除算の余り（被除数と同符号）。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/math.scm](../../ulisp/lib/math.scm) (新規作成: square, remainder, gcd-2, lcm-2, expt)
- [x] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld) (math.scm の include 追加)
- [x] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (gcd, lcm の可変長脱糖展開)
- [x] [ulisp/passes/020_macro_expander.scm](../../ulisp/passes/020_macro_expander.scm) (core-form-or-primitive 登録)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (ULISP_STD_LIBS への math.scm 追加)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (算術手続きテスト追加)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/558-implement-r7rs-elementary-integer-math-procedures`

1. 手続きアルゴリズムの設計・実装:
   - `square`: `(lambda (x) (* x x))`
   - `remainder`: 既存の `%` または `/` と `*` による整商・余り算出。
   - `gcd`: ユークリッドの互除法。可変長引数に対応し、2数の gcd を fold。
   - `lcm`: `(/ (* (abs a) (abs b)) (gcd a b))`（0 を含む場合の特別扱い）。可変長引数対応。
   - `expt`: 整数指数に対する O(log n) 繰り返し二乗法。`z2 = 0` の場合は 1。
2. ライブラリ構成と Makefile 連携:
   - `ulisp/lib/math.scm` を作成し、`Makefile` の標準ライブラリ群（`test_stdlib` 結合対象）に追加。
3. テストの作成・実行:
   - 基本演算、境界値（0、負の数、指数 0 など）の正確性検証。
4. 全体テストの実行・パス確認 (`./test.sh`, `./test_c.sh`)。
5. `ulisp/docs/r7rs_specification_compliance.md` の更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `square`, `gcd`, `lcm`, `expt`, `remainder` が実装されていること。
- [x] 0 や負数を含む境界値テストが正常に動作すること。
- [x] `tests/test_stdlib_r7rs.scm` にテストが追加され合格すること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` の対象項目が更新されていること。
