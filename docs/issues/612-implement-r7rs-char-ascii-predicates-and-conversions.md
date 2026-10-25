---
ID: 612
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS (scheme char) ASCII 文字・文字列述語群および大小文字変換手続きの実装 (ID: 612)

## 1. 概要 / Summary
R7RS-small §6.6, §6.7 および `(scheme char)` で規定されている文字・文字列の大文字小文字無視（Case-insensitive）比較述語、文字種判定述語、および大小文字変換手続きを実装する。
初期フェーズとして標準 ASCII / 基本ラテン文字セットを対象とし、コンパイラおよび標準ライブラリにおけるテキスト処理基盤を強化する。

主な対象手続き:
1. 大文字小文字同一視文字比較: `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`
2. 文字種判定述語: `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`, `digit-value`
3. 文字大小変換: `char-upcase`, `char-downcase`, `char-foldcase`
4. 大文字小文字同一視文字列比較: `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?`
5. 文字列大小変換: `string-upcase`, `string-downcase`, `string-foldcase`

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §6.6: Characters (`char-ci*`, `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`, `digit-value`, `char-upcase`, `char-downcase`, `char-foldcase`)
  - §6.7: Strings (`string-ci*`, `string-upcase`, `string-downcase`, `string-foldcase`)
  - §5.6 / §5.1: `(scheme char)`
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.6, 6.7), §1.4 (`(scheme char)`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/char.scm](../../ulisp/lib/char.scm): 文字判定・変換手続き群の実装
- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm): 文字列の case-insensitive 比較および変換手続きの実装
- [ ] [ulisp/lib/scheme/char.sld](../../ulisp/lib/scheme/char.sld): `(scheme char)` ライブラリ定義およびエクスポート
- [ ] [ulisp/tests/test_char.scm](../../ulisp/tests/test_char.scm): 文字・文字列述語の網羅的テストスイート
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): 準拠ステータス更新 (20% → 80%+)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/612-implement-r7rs-char-ascii-predicates-and-conversions`

1. `char->integer` / `integer->char` を基盤として、ASCII コードポイント範囲（`A-Z`: 65-90, `a-z`: 97-122, `0-9`: 48-57, 空白・改行・タブ等）に基づく高速な文字分類・変換関数を `ulisp/lib/char.scm` に実装。
2. `char-foldcase` / `char-downcase` による正規化を介して `char-ci*` 比較述語群（複数引数対応）を構成。
3. `string-map` を活用して `string-upcase`, `string-downcase`, `string-foldcase` を実装。
4. 文字列同士の文字単位 `char-ci*` 比較を行う `string-ci*` 述語群を実装。
5. `(scheme char)` SLD を更新し、すべての新設手続きをエクスポートする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(char-ci=? #\a #\A)` が `#t` を返すこと。
- [ ] `(char-alphabetic? #\Z)`, `(char-numeric? #\5)`, `(char-whitespace? #\space)` 等が正しく判定されること。
- [ ] `(digit-value #\7)` が `7` を返し、非数字文字に対して `#f` を返すこと。
- [ ] `(string-ci<? "abc" "ABD")` が `#t` を返すこと。
- [ ] `(string-upcase "Hello, World!")` が `"HELLO, WORLD!"` を返すこと。
- [ ] `(import (scheme char))` から全手続きが利用可能であること。
