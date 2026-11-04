---
ID: 715
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS §6.2.6 数値塔リテラル入出力 (number->string 基数対応・string->number / read / write 拡張) の実装 (ID: 715)

## 1. 概要 / Summary
R7RS-small §6.2.6 および §7.1.1 の数値外部表現仕様に完全準拠するため、`number->string` の可変基数 (`radix` = 2, 8, 10, 16) および有理数・浮動小数点数・複素数フォーマット出力を実装する。あわせて `string->number`、S 式リーダー (`read`)、およびプリンタ (`write`/`display`) において、有理数リテラル (`p/q`)、小数・指数表記 (`3.14`, `1e-5`)、正確性プレフィックス (`#e`, `#i`)、IEEE 特殊値 (`+inf.0`, `-inf.0`, `+nan.0`)、および複素数リテラル (`a+bi`, `r@theta`, `+i`, `-i`) の読み書きを完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.6 (`number->string`, `string->number`), §7.1.1 (Lexical structure: `<number>`)
  - 先行依存: [Issue #711](711-implement-r7rs-exact-rationals-rounding-and-rationalize.md), [Issue #712](712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md), [Issue #714](714-implement-r7rs-scheme-complex-arithmetic-library.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [string.scm](../../../ulisp/lib/string.scm)
- [x] [reader.scm](../../../ulisp/lib/reader.scm)
- [x] [printer.scm](../../../ulisp/lib/printer.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting`

1. **`number->string` 可変基数 (`radix` = 2, 8, 10, 16) および全数値塔出力 ([string.scm](../../../ulisp/lib/string.scm), [printer.scm](../../../ulisp/lib/printer.scm))**:
   - `number->string` を `case-lambda` で 1 引数 `(z)` および 2 引数 `(z radix)` に対応する。
   - Fixnum の基数 2 / 8 / 10 / 16 フォーマット（16 進は小文字 `a`–`f`）、`<ratnum>` の `n/d` 出力、`<flonum>` の小数点出力（`3.5`, `0.0`, `+inf.0`, `-inf.0`, `+nan.0`）、および `<compnum>` の `a+bi` / `a-bi` 出力を実装する。
   - `printer.scm` において `write` / `display` / `write-shared` が全数値塔オブジェクトを `number->string` で出力するように統合する。
2. **`string->number` および `read` の全数値塔リテラル構文解析 ([reader.scm](../../../ulisp/lib/reader.scm))**:
   - プレフィックス `#e` (exact), `#i` (inexact), `#b`, `#o`, `#d`, `#x` の任意の順序組み合わせに対応する。
   - IEEE 特殊値 (`+inf.0`, `-inf.0`, `+nan.0`, `-nan.0`)、有理数 (`p/q`)、小数・指数表記 (`3.14`, `.5`, `1.5e2`, `2e-3`)、直交複素数 (`3+4i`, `3-4i`, `+i`, `-i`, `+3i`)、および極座標複素数 (`r@theta`) を解析する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `number->string` (基数 2, 8, 10, 16 + 全数値塔) および `string->number` / `read` / `write` が実装され、[test_numeric_tower.scm](../../../ulisp/tests/test_numeric_tower.scm) が PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability test_numeric_tower` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) の該当項目が更新されていること。

