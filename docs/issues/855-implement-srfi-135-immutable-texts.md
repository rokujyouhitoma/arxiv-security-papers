---
ID: 855
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 135 不変テキストライブラリ ((scheme text)) の実装 (ID: 855)

## 1. 概要 / Summary
R7RS-large Red Edition に規定される SRFI 135 (Immutable Texts) は、効率的なメモリ共有、高速な部分文字列スライシング ($O(1)$)、および不変性を保証するテキストシーケンス型である。
長大なテキストを扱うコンパイラやパーサにおいて不可欠なデータ型でありながら、現状の ULisp では「× (未サポート)」となっている。
本 Issue では、2分木構造（Rope / Chunked text）に基づく `(scheme text)` および `(srfi 135)` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Red Edition: `(scheme text)`
  - SRFI 135: Immutable Texts
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/text.scm](../../ulisp/lib/text.scm) (新規作成)
- [ ] [ulisp/lib/scheme/text.sld](../../ulisp/lib/scheme/text.sld) (新規作成)
- [ ] [ulisp/lib/srfi/135.sld](../../ulisp/lib/srfi/135.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_135.scm](../../ulisp/tests/test_srfi_135.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/855-implement-srfi-135-immutable-texts`

1. **Text Representation**:
   - Leaf (Flat string chunk) および Concatenation Node (Rope) による平衡木表現。
   - `text?`, `make-text`, `text`, `text-length`, `text-ref`, `subtext`.
2. **Text Operations & Iterators**:
   - `text-append`, `text-concatenate`, `text-tabulate`, `text-unfold`, `text-unfold-right`.
   - `text-map`, `text-for-each`, `text-fold`, `text-fold-right`, 述語 `text=?`, `text<?` 等。
3. **文字列・リスト・文字セット相互変換**:
   - `string->text`, `text->string`, `string->text-range`, `text->string-range`。
4. **テストスイート**:
   - 大規模テキストの反復スライスおよびメモリ消費量・スタック安全性の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme text)` / `(srfi 135)` が定義され、全必須手続きがエクスポートされること。
- [ ] 部分文字列スライスや連結が定数時間・対数時間で高速動作すること。
- [ ] `test_srfi_135.scm` が全 PASS すること。
