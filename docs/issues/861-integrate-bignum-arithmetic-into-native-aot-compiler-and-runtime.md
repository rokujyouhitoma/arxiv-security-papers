---
ID: 861
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 多倍長整数 (Bignum) のネイティブ AOT ランタイム完全統合と Tangerine Tower 適合 (ID: 861)

## 1. 概要 / Summary
R7RS-large Tangerine Edition において義務付けられる完全数値塔 (Full Numeric Tower) に適合するためには、62-bit 即値 Fixnum を超える任意精度整数 (Bignums) のシームレスなサポートが不可欠である。
先行 Issue #832 において純粋 Scheme 製多倍長整数ライブラリ `ulisp/lib/bignum.scm` が整備されたが、ネイティブ AOT コンパイラ（x86-64 / C バックエンド）および LIR レベルでの自動オーバーフロー検知と Bignum への昇格 (Promotion)・降格 (Demotion) が未結合であった。
本 Issue では、Fixnum 演算オーバーフロー時に自動的にヒープ Bignum オブジェクトをアロケート・演算するパスを AOT ランタイムに統合する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Tangerine Edition (Tangerine Tower / Arbitrary Precision Integers)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2
  - [Issue #832: Implement pure scheme bignum and IEEE 754 conversion libraries](closed/832-implement-pure-scheme-bignum-and-ieee-754-conversion-libraries.md)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/bignum.scm](../../ulisp/lib/bignum.scm)
- [ ] [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm)
- [ ] [ulisp/tests/test_bignum.scm](../../ulisp/tests/test_bignum.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/861-integrate-bignum-arithmetic-into-native-aot-compiler-and-runtime`

1. **オーバーフロー検知と Bignum 昇格**:
   - LIR 加減乗算において CPU のオーバーフローフラグ（OF）を検査。
   - オーバーフロー発生時、Fixnum から 64-bit リム配列を持つヒープ Bignum への昇格ハンドラを呼び出し。
2. **算術手続きとリーダー/プリンタの Bignum 統合**:
   - `math.scm` の `num+`, `num-`, `num*`, `num/` に Bignum 型判定を追加。
   - リーダー (`reader.scm`) において 62-bit を超える整数リテラルを直接 Bignum として構築。
   - プリンタ (`printer.scm`) において任意桁数の 10 進数文字列出力を保証。
3. **回帰テスト**:
   - 階乗 $100!$ や $2^{1000}$ の計算精度および性能特性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 62-bit 範囲外の整数演算がオーバーフローせずに正確な多倍長整数として計算されること。
- [ ] $100!$ や巨大な整数の相互変換 (`number->string`, `string->number`) が正確に行えること。
- [ ] `test_bignum.scm` が全 PASS すること。
