---
ID: 858
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 143 Fixnums 特化高速演算ライブラリおよび (scheme fixnum) の実装 (ID: 858)

## 1. 概要 / Summary
R7RS-large Tangerine Edition において定められている SRFI 143 (Fixnums) は、プラットフォーム固有の固定長整数 (Fixnum) に特化した型安全かつアンボックス高速演算 API を規定する。
ULisp はスタンドアロン 62-bit 即値 Fixnum アーキテクチャを採用しているにもかかわらず、`(scheme fixnum)` や `(srfi 143)` としての標準ライブラリが未提供であった。
本 Issue では、SRFI 143 準拠の Fixnum 専用算術・比較・ビット演算ライブラリを実装し、コンパイラの AOT アンボクシング最適化と連携させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Tangerine Edition: `(scheme fixnum)`
  - SRFI 143: Fixnums
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/fixnum.scm](../../ulisp/lib/fixnum.scm) (新規作成)
- [ ] [ulisp/lib/scheme/fixnum.sld](../../ulisp/lib/scheme/fixnum.sld) (新規作成)
- [ ] [ulisp/lib/srfi/143.sld](../../ulisp/lib/srfi/143.sld) (新規作成)
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm)
- [ ] [ulisp/tests/test_srfi_143.scm](../../ulisp/tests/test_srfi_143.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/858-implement-srfi-143-fixnums-and-scheme-fixnum`

1. **定数と述語**:
   - `fx-width` (62), `fx-greatest`, `fx-least`, `fixnum?`, `fx=?`, `fx<?`, `fx>?`, `fx<=?`, `fx>=?`, `fxzero?`, `fxpositive?`, `fxnegative?`, `fxodd?`, `fxeven?`.
2. **算術・丸め演算**:
   - `fx+`, `fx-`, `fxneg`, `fx*`, `fxquotient`, `fxremainder`, `fxabs`, `fxsquare`, `fxsqrt`.
   - `fxfloor/`, `fxfloor-quotient`, `fxfloor-remainder`, `fxtruncate/`, `fxtruncate-quotient`, `fxtruncate-remainder`.
3. **ビット演算・パッカ**:
   - `fxnot`, `fxand`, `fxior`, `fxxor`, `fxarithmetic-shift`, `fxbit-count`, `fxlength`, `fxif`, `fxbit-set?`, `fxcopy-bit`, `fxfirst-set-bit`.
4. **コンパイラ連携**:
   - `090_rtyper.scm` において `fx*` 系手続きを純粋機械語命令（インライン算術）へダイレクトにマッピング。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme fixnum)` および `(srfi 143)` が定義され、すべての `fx*` 手続きが利用可能であること。
- [ ] 62-bit 境界（最大値・最小値）でのオーバーフロー・アンダーフロー動作が検証されていること。
- [ ] `test_srfi_143.scm` が全 PASS すること。
