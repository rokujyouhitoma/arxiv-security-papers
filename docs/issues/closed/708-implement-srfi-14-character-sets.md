---
ID: 708
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 14 (scheme charset) 文字集合ライブラリの実装 (ID: 708)

## 1. 概要 / Summary
R7RS-large Red Edition の中核ライブラリであり、かつ正規表現エンジン (SRFI 115) やパーサの基盤となる **SRFI 14 (`(scheme charset)` / `(srfi 14)` Character-set Library)** を実装する。ビットマップ（バイトベクタ）表現を用いて AOT コンパイラ上で $O(1)$ の高速な文字集合代数演算（和・積・差・排他的論理和・補集合）および標準文字集合定数群（`char-set:letter`, `char-set:digit`, `char-set:whitespace`, `char-set:ascii`, `char-set:full` 等）を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 14: Character-set Library](https://srfi.schemers.org/srfi-14/srfi-14.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [charset.scm](../../../ulisp/lib/charset.scm) (新規)
- [x] [charset.sld](../../../ulisp/lib/scheme/charset.sld) (新規)
- [x] [14.sld](../../../ulisp/lib/srfi/14.sld) (新規)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_charset.scm](../../../ulisp/tests/test_charset.scm) (新規)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/708-implement-srfi-14-character-sets`

1. **内部表現とビットマップ演算 ([charset.scm](../../../ulisp/lib/charset.scm))**:
   - 2要素ベクタ `#(ulisp-char-set-tag <32-byte-bytevector>)` として 0..255 コードポイントのビット集合を保持。
   - 2引数ヘルパ `%cs-bv-set!` を介して `bytevector-u8-set!` を行い、スタックフレーム安全性を確保。
2. **全 SRFI 14 手続き・標準文字集合の実装**:
   - 述語・比較・ハッシュ: `char-set?`, `char-set=`, `char-set<=`, `char-set-hash`
   - カーソル・反復: `char-set-cursor`, `char-set-ref`, `char-set-cursor-next`, `end-of-char-set?`, `char-set-fold`, `char-set-unfold`, `char-set-unfold!`, `char-set-for-each`, `char-set-map`
   - 生成・変換: `char-set-copy`, `char-set`, `list->char-set`, `list->char-set!`, `string->char-set`, `string->char-set!`, `char-set-filter`, `char-set-filter!`, `ucs-range->char-set`, `ucs-range->char-set!`, `->char-set`
   - クエリ: `char-set-size`, `char-set-count`, `char-set->list`, `char-set->string`, `char-set-contains?`, `char-set-every`, `char-set-any`
   - 集合代数（純粋版および線形更新 `!` 版）: `char-set-adjoin`, `char-set-delete`, `char-set-adjoin!`, `char-set-delete!`, `char-set-complement`, `char-set-union`, `char-set-intersection`, `char-set-difference`, `char-set-xor`, `char-set-diff+intersection`, `char-set-complement!`, `char-set-union!`, `char-set-intersection!`, `char-set-difference!`, `char-set-xor!`, `char-set-diff+intersection!`
   - 標準定数 17 種: `char-set:lower-case`, `char-set:upper-case`, `char-set:title-case`, `char-set:letter`, `char-set:digit`, `char-set:letter+digit`, `char-set:graphic`, `char-set:printing`, `char-set:whitespace`, `char-set:iso-control`, `char-set:punctuation`, `char-set:symbol`, `char-set:hex-digit`, `char-set:blank`, `char-set:ascii`, `char-set:empty`, `char-set:full`
3. **ライブラリ定義・テスト**:
   - `(scheme charset)` および `(srfi 14)` の `.sld` ファイルを作成し、[test_charset.scm](../../../ulisp/tests/test_charset.scm) で全手続き・定数を AOT 検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] SRFI 14 全手続きおよび全 17 標準文字集合定数が実装され、AOT テスト [test_charset.scm](../../../ulisp/tests/test_charset.scm) が exit code 0 で PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) で SRFI 14 (`(scheme charset)`) が **◎** に更新されていること。
