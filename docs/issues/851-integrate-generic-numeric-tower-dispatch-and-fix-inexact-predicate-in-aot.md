---
ID: 851
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] AOT ネイティブ算術演算子における数値塔ジェネリックディスパッチ統合と inexact? 判定の是正 (ID: 851)

## 1. 概要 / Summary
ULisp では `ulisp/lib/math.scm` にて有理数 `<ratnum>`、浮動小数点数 `<flonum>`、複素数 `<compnum>` を含む数値塔とジェネリック演算（`num+`, `num-`, `num*`, `num/`, `num=` 等）が実装されている。
しかし、AOT コンパイラ（`ulisp/lir/129_lir_primitives.scm`）では `+`, `-`, `*`, `/`, `=` が直接 62-bit Fixnum CPU 命令に結びつけられており、AOT コンパイルされた Scheme コードで `(+ 1/2 1/3)` などを評価すると不正なポインタ演算となってしまう。また `inexact?` 述語が AOT コンパイラ内で無条件に `#f` を返す定数出力となっている。
本 Issue では、AOT ネイティブパスにおいて型タグ判定に基づくファストパス（Fixnum 同士）とスローパス（数値塔ジェネリックディスパッチ）の分岐生成を導入し、R7RS 完全数値塔の AOT 動作を保証する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-small Section 6.2 (Numbers: 6.2.6 Numerical operations)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.2 数値演算)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm)
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm)
- [ ] [ulisp/lib/math.scm](../../ulisp/lib/math.scm)
- [ ] [ulisp/lib/predicates.scm](../../ulisp/lib/predicates.scm)
- [ ] [ulisp/tests/test_numeric_tower.scm](../../ulisp/tests/test_numeric_tower.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/851-integrate-generic-numeric-tower-dispatch-and-fix-inexact-predicate-in-aot`

1. **型推論とファストパス最適化 (`090_rtyper.scm`)**:
   - オペランドの両方が静的に Fixnum と確定している場合（例: `fxadd1`, 整数の定数演算）は、既存のインライン機械語命令（`add`, `sub` 等）を維持。
2. **算術 LIR 生成のジェネリックフォールバック (`129_lir_primitives.scm`)**:
   - `+`, `-`, `*`, `/`, `=` において、両オペランドが Fixnum タグ（最下位 2-bit `00b`）を満たすかチェックするタグテスト分岐を生成。
   - いずれかがヒープ数値オブジェクトの場合、ランタイムの `num+`, `num-`, `num*`, `num/`, `num=` へジャンプするスローパスを生成。
3. **`inexact?` LIR プリミティブの修正**:
   - ハードコードされた `#f` を撤廃し、引数が `<flonum>` タグまたは不正確成分を持つ `<compnum>` タグであるかを検査する LIR を出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] AOT コンパイルされたバイナリ上で `(+ 1/2 1/3)` が正確有理数 `5/6` を返すこと。
- [ ] `(= 1 1.0)` や `(= 2 4/2)` が正しく真偽値を判定すること。
- [ ] `(inexact? 1.5)` が AOT ネイティブコードで `#t` を返し、`(inexact? 1)` が `#f` を返すこと。
- [ ] `test_numeric_tower.scm` が AOT ネイティブ実行で全 PASS すること。
