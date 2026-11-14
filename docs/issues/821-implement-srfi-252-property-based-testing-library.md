---
ID: 821
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 252 プロパティベーステストライブラリ (srfi 252) と決定論的ジェネレータ群の実装 (ID: 821)

## 1. 概要 / Summary
エッジケースの網羅や数学的性質・コンパイラ不変条件（ラウンドトリップ性・最適化前後の意味保存性など）を自動検証するため、**SRFI 252: Property Testing** を ULisp 標準ライブラリ（`ulisp/lib/property.scm` および `ulisp/lib/srfi/252.sld`）として実装する。
ULisp に実装済みの **SRFI 128 (`(scheme comparator)`)**、**SRFI 158 (`(scheme generator)`)**、[tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm) の決定論的シード付き PRNG、および [Issue #819](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md) の **SRFI 64 (`(srfi 64)`)** を統合し、再現可能なプロパティベーステストとコンパイラ AST ファジング用ジェネレータを提供する。

---

## 2. トレーサビリティ / Traceability
- [SRFI 252: Property Testing](https://srfi.schemers.org/srfi-252/srfi-252.html)
- [Issue #819 R7RS-large / SRFI 64 テストスイート標準ライブラリ (srfi 64) の実装](819-implement-srfi-64-test-suites-library-and-custom-test-runners.md)
- [Issue #701 R7RS-large / SRFI 128 (scheme comparator) 第一級比較器ライブラリの実装](closed/701-implement-srfi-128-comparators.md)
- [Issue #704 R7RS-large / SRFI 158 (scheme generator) 汎用ジェネレータ・アキュムレータライブラリの実装](closed/704-implement-srfi-158-generators-and-accumulators.md)
- [ULisp R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/property.scm](../../ulisp/lib/property.scm) (新規作成: SRFI 252 プロパティ検証・ジェネレータ群・反例縮小レポート実装)
- [ ] [ulisp/lib/srfi/252.sld](../../ulisp/lib/srfi/252.sld) (新規作成: `(srfi 252)` ライブラリ定義)
- [ ] [ulisp/tests/test_srfi_252.scm](../../ulisp/tests/test_srfi_252.scm) (新規作成: SRFI 252 単体テストおよび数値塔・Reader/Printer・CP0 パス性質テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_252` ターゲットおよび `lint_sexpr` への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/821-implement-srfi-252-property-based-testing-library`

1. **プロパティ検証 API と SRFI 64 ランナー統合の実装**:
   - `test-property`, `test-property-expect-fail`, `test-property-skip`, `test-property-error`, `test-property-expect-error`, `property-test-runner` を実装し、SRFI 64 のテストスイート内でシームレスに実行・集計できるようにする。
   - 失敗時の入力引数（反例: Counterexample）と決定論的 PRNG シードをテストランナーに記録・表示し、100% 再現可能にする。
2. **標準型ジェネレータ群および S 式 AST ジェネレータの実装**:
   - SRFI 252 標準ジェネレータ（`boolean-generator`, `bytevector-generator`, `char-generator`, `string-generator`, `symbol-generator`, `fixnum-generator`, `integer-generator`, `exact-rational-generator`, `inexact-generator`, `real-generator`, `complex-generator`, `number-generator`, `list-generator-of`, `pair-generator-of`, `vector-generator-of`, `procedure-generator-of`）を実装する。
   - ULisp コンパイラパス検証用の拡張として、深さ制限付き純粋 S 式を生成する `sexpr-generator` を提供する。
3. **ULisp コア機能に対するプロパティテストの整備**:
   - `ulisp/tests/test_srfi_252.scm` にて、① 有理数 `<ratnum>` の正規化不変条件と算術交換・結合法則、② `write` / `read` および `number->string` / `string->number` のラウンドトリップ性、③ `cp0-optimize` 適用前後の評価結果一致性を検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(import (srfi 252))` により `test-property` 系構文および各種ジェネレータが仕様通り動作すること。
- [ ] 反例検出時に失敗した生成入力値とシードが明示的にレポートされること。
- [ ] `make -C ulisp test_srfi_252` および `make -C ulisp test_r7rs_traceability lint_sexpr` が 100% PASS すること。
- [ ] ドキュメント内のすべてのリンクが相対パスで記述されていること。