---
ID: 652
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS §6.2.6 string->number の可変基数 (2/8/10/16進数) 対応と数値リテラルパースの拡充 (ID: 652)

## 1. 概要 / Summary
R7RS-small §6.2.6 で規定されている `(string->number <string> [<radix>])` を完全サポートする。
現状の ULisp では S 式リーダー内部で 10 進数のみを解析しているが、第 2 引数による基数指定（`radix`: 2, 8, 10, 16）および基数プレフィックス（`#b`, `#o`, `#d`, `#x`）、明示的な正負号（`+`, `-`）を解釈できるようにする。

---

## 2. トレーサビリティ / Traceability
- R7RS-small: Section 6.2.6 (Numerical operations - string->number)
- 仕様リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2.6)
- 関連モジュール: [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm), [ulisp/lib/string.scm](../../ulisp/lib/string.scm), [ulisp/lib/math.scm](../../ulisp/lib/math.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm)
- [ ] [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
- [ ] [ulisp/lib/scheme/base.sld](../../ulisp/lib/scheme/base.sld)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)
- [ ] [ulisp/tests/test_string_to_number.scm](../../ulisp/tests/test_string_to_number.scm) (新規テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/652-implement-r7rs-string-to-number-radix-support`

1. プレフィックス (`#b`, `#o`, `#d`, `#x`) の有無を判定し、デフォルト基数（引数で指定された基数、または 10）を設定。
2. プレフィックスで指定された基数と第 2 引数が矛盾する場合のバリデーション（`#f` 返却）。
3. 指定基数の有効数字文字（0-1, 0-7, 0-9, 0-9a-fA-F）を左から右へホーナー法（Horner's method）で 62-bit Fixnum に変換。
4. オーバーフロー判定を行い、Fixnum 範囲外または不正文字を含む場合は `#f` を返却。
5. `(scheme base)` からエクスポートし、リーダー（`read`）ともコード共通化を図る。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(string->number "1010" 2)` => `10`、`(string->number "#xff")` => `255` 等が正しく評価されること。
- [ ] 不正入力に対して `#f` を安全に返却し、クラッシュしないこと。
- [ ] `ref_r7rs_compliance.md` の §6.2.6 `string->number` のステータスを `◎` に更新すること。

