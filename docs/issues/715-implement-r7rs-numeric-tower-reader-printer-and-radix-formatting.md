---
ID: 715
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.2.6 数値塔リテラル入出力 (number->string 基数対応・string->number / read / write 拡張) の実装 (ID: 715)

## 1. 概要 / Summary
R7RS-small §6.2.6 および §7.1.1 の数値外部表現仕様に完全準拠するため、`number->string` の可変基数 (`radix` = 2, 8, 10, 16) および有理数・浮動小数点数・複素数フォーマット出力を実装する。あわせて `string->number`、S 式リーダー (`read`)、およびプリンタ (`write`/`display`) において、有理数リテラル (`p/q`)、小数・指数表記 (`3.14`, `1e-5`)、正確性プレフィックス (`#e`, `#i`)、IEEE 特殊値 (`+inf.0`, `-inf.0`, `+nan.0`)、および複素数リテラル (`a+bi`, `r@theta`, `+i`, `-i`) の読み書きを完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§1.3.2 数値演算 6.2)
  - R7RS-small §6.2.6 (`number->string`, `string->number`), §7.1.1 (Lexical structure: `<number>`)
  - 先行依存: [Issue #711](711-implement-r7rs-exact-rationals-rounding-and-rationalize.md), [Issue #712](712-implement-r7rs-inexact-flonums-exactness-conversions-and-ieee-predicates.md), [Issue #714](714-implement-r7rs-scheme-complex-arithmetic-library.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [string.scm](../../ulisp/lib/string.scm)
- [ ] [reader.scm](../../ulisp/lib/reader.scm)
- [ ] [printer.scm](../../ulisp/lib/printer.scm)
- [ ] [comparator.scm](../../ulisp/lib/comparator.scm)
- [ ] [test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/715-implement-r7rs-numeric-tower-reader-printer-and-radix-formatting`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

