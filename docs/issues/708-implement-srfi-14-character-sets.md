---
ID: 708
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 14 (scheme charset) 文字集合ライブラリの実装 (ID: 708)

## 1. 概要 / Summary
R7RS-large Red Edition の中核ライブラリであり、かつ正規表現エンジン (SRFI 115) やパーサの基盤となる **SRFI 14 (`(scheme charset)` / `(srfi 14)` Character-set Library)** を実装する。ビットマップ（バイトベクタ）表現を用いて AOT コンパイラ上で $O(1)$ の高速な文字集合代数演算（和・積・差・排他的論理和・補集合）および標準文字集合定数群（`char-set:letter`, `char-set:digit`, `char-set:whitespace`, `char-set:ascii`, `char-set:full` 等）を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 14: Character-set Library](https://srfi.schemers.org/srfi-14/srfi-14.html)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [charset.scm](../../ulisp/lib/charset.scm) (新規)
- [ ] [charset.sld](../../ulisp/lib/scheme/charset.sld) (新規)
- [ ] [14.sld](../../ulisp/lib/srfi/14.sld) (新規)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_charset.scm](../../ulisp/tests/test_charset.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/708-implement-srfi-14-character-sets`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

