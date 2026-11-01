---
ID: 662
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 141 6モード整数除算手続き群の実装 (ID: 662)

## 1. 概要 / Summary
R7RS-large Tangerine Edition および SRFI 141 (Integer Division) に準拠し、6つの数学的丸めモード（floor, ceiling, truncate, round, euclidean, centered）に対応した整数除算・剰余演算手続き群を完全実装する。
ULisp では現在 `floor/`, `truncate/`, `quotient`, `modulo` などの一部のみサポート（△）しているが、SRFI 141 で規定される全 18 演算（単値除算 6 種、剰余 6 種、多値ペア 6 種）を整備し、暗号・数値アルゴリズムにおける除算の厳密性を向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 141: Integer Division
  - R7RS-large Tangerine Edition (Numerics)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2 Tangerine Edition
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/math.scm](../ulisp/lib/math.scm) (除算・剰余アルゴリズム実装)
- [ ] [ulisp/lib/srfi/141.sld](../ulisp/lib/srfi/141.sld) (新規 SRFI 141 ライブラリ定義)
- [ ] [ulisp/lib/scheme/division.sld](../ulisp/lib/scheme/division.sld) (R7RS-large エクスポート)
- [ ] [ulisp/tests/test_srfi_141_division.scm](../ulisp/tests/test_srfi_141_division.scm) (新規単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/662-implement-srfi-141-integer-division`

1. 以下の 6 モードそれぞれについて、商（quotient）、剰余（remainder）、および多値ペア（slash）を実装：
   - Floor: `floor/`, `floor-quotient`, `floor-remainder` (実装済み)
   - Truncate: `truncate/`, `truncate-quotient`, `truncate-remainder` (実装済み)
   - Ceiling: `ceiling/`, `ceiling-quotient`, `ceiling-remainder`
   - Round: `round/`, `round-quotient`, `round-remainder` (最近接偶数への丸め)
   - Euclidean: `euclidean/`, `euclidean-quotient`, `euclidean-remainder` (剰余が常に非負)
   - Centered: `centered/`, `centered-quotient`, `centered-remainder` (剰余が区間 `[-d/2, d/2)` に入る)
2. ゼロ除算時の例外送出とオーバーフロー保護の徹底。
3. `(srfi 141)` および `(scheme division)` ライブラリ定義を作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] SRFI 141 規定の全 18 手続きが正確な結果を返す
- [ ] 負の除数・被除数に対する境界条件テストがすべて PASS する
- [ ] `(srfi 141)` ライブラリとしてインポート可能
- [ ] `make test` を通過する

