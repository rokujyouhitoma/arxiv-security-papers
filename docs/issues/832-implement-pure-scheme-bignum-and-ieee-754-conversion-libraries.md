---
ID: 832
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 純粋 Scheme による多倍長整数 (Bignum) および IEEE 754 相互変換標準ライブラリの実装 (ID: 832)

## 1. 概要 / Summary
外部の C ライブラリ（GMP や外部 libc）に一切依存せず、純粋な Scheme（ポータブル R7RS 準拠コード）のみで記述された多倍長整数ライブラリ（`ulisp/lib/bignum.scm`）および 10 進表記 ↔ IEEE 754 浮動小数点数相互変換モジュール（`ulisp/lib/ieee754.scm`）を実装する。
これにより、コンパイラ内部における 64bit 定数演算や C プリプロセッサの定数式評価（$2^{64}$ を法とする演算含む）を確実に担保するとともに、Scheme 処理系自身の数値塔（Exact/Inexact、任意精度整数、浮動小数点リテラル構文解析）の完全自給自足（Self-contained）を達成する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (A1: 多倍長整数ライブラリ, A2: 10進表記から IEEE 754 への変換, B1: プリプロセッサ #if 式)
- **関連 Issue**: #617 (Self-Contained Bootstrap Chain), #825 (AST Evaluator / CTFE), #828 (Overflow Arithmetic)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/bignum.scm](../../ulisp/lib/bignum.scm): 任意精度多倍長整数演算（加減乗除、ビット演算、$2^{64}$ 法演算）の実装
- [ ] [ulisp/lib/ieee754.scm](../../ulisp/lib/ieee754.scm): 正確な丸め規則（Round to nearest, ties to even）に基づく 10 進浮動小数点文字列 ↔ 64bit ビット列変換
- [ ] [ulisp/tests/test_bignum.scm](../../ulisp/tests/test_bignum.scm): 多倍長整数演算の単体テスト
- [ ] [ulisp/tests/test_ieee754.scm](../../ulisp/tests/test_ieee754.scm): Clang 出力ビット列との相互比較テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/832-pure-scheme-bignum-ieee754`

1. 多倍長整数（Bignum）エンジンの実装：
   - 32bit または 60bit を 1 リム（Limb）とするベクタ表現を採用。
   - Karatsuba 乗算または素朴な多倍長四則演算の実装。
   - 符号なし 64bit ラップアラウンド演算（Modulo $2^{64}$）専用の高速ルーチンの提供。
2. IEEE 754 双方向パーサ／フォーマッタの実装：
   - Clinger's Algorithm または Ryū / Grisu アルゴリズムの Scheme 移植による、正しく丸められた 64bit 浮動小数点ビット列（`double`）の生成。
   - サブノーマル数（非正規化数）、無限大（Inf）、NaN（Quiet/Signaling）のビットパターン厳密処理。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 64bit を超える巨大整数の加減乗除およびビットシフトが、Gaurche や外部 GMP と同一の結果を返すこと。
- [ ] `0.5`, `1e308`, `1e-308`, `0.1` などの浮動小数点リテラルから生成された 64bit ビット列が、Clang/GCC のパース結果と 1 ビットの狂いもなく完全一致すること。
- [ ] 単体テスト `test_bignum.scm` および `test_ieee754.scm` が全項目合格すること。
