---
ID: 662
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] R7RS-large / SRFI 141 6モード整数除算手続き群の実装 (ID: 662)

## 1. 概要 / Summary
R7RS-large Tangerine Edition および SRFI 141 (Integer Division) に準拠し、6つの数学的丸めモード（floor, ceiling, truncate, round, euclidean, centered）に対応した整数除算・剰余演算手続き群を完全実装する。
ULisp では現在 `floor/`, `truncate/`, `quotient`, `modulo` などの一部のみサポート（△）していたが、SRFI 141 で規定される全 18 演算（単値除算商 6 種、剰余 6 種、多値ペア 6 種）を整備し、暗号・数値・ハッシュアルゴリズムにおける除算の厳密性を向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - SRFI 141: Integer Division
  - R7RS-large Tangerine Edition (Numerics)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2 Tangerine Edition
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/math.scm](../ulisp/lib/math.scm) (除算・剰余アルゴリズム実装)
- [x] [ulisp/lib/srfi/141.sld](../ulisp/lib/srfi/141.sld) (新規 SRFI 141 ライブラリ定義)
- [x] [ulisp/lib/scheme/division.sld](../ulisp/lib/scheme/division.sld) (R7RS-large エクスポート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../ulisp/docs/ref_r7rs_compliance.md) (R7RS 準拠状況テーブル更新)
- [x] [ulisp/tests/test_srfi_141_division.scm](../ulisp/tests/test_srfi_141_division.scm) (新規単体テスト)
- [x] [ulisp/Makefile](../ulisp/Makefile) (テストターゲット統合)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/662-implement-srfi-141-integer-division`

1. **6つの数学的丸めモードの定義**:
   被除数を $n$、除数を $d$ ($d \ne 0$) とする。常に $n = q \times d + r$ を満たす。
   - **Floor**:
     $q = \lfloor n/d \rfloor$。$r$ は $d$ と同符号または 0。
     - `floor/`, `floor-quotient`, `floor-remainder`
   - **Truncate**:
     $q = \text{trunc}(n/d)$ (0への丸め)。$r$ は $n$ と同符号または 0。
     - `truncate/`, `truncate-quotient`, `truncate-remainder`
   - **Ceiling**:
     $q = \lceil n/d \rceil$。$r$ は $-d$ と同符号または 0。
     - `ceiling/`, `ceiling-quotient`, `ceiling-remainder`
   - **Round**:
     $q$ は $n/d$ に最も近い整数（タイの場合は最も近い偶数）。
     - `round/`, `round-quotient`, `round-remainder`
   - **Euclidean**:
     $r$ は常に $0 \le r < |d|$。ユークリッド除算定理に厳密に従う。
     - `euclidean/`, `euclidean-quotient`, `euclidean-remainder`
   - **Centered**:
     $r$ は区間 $-|d|/2 \le r < |d|/2$ に収まる。
     - `centered/`, `centered-quotient`, `centered-remainder`

2. **アルゴリズム実装**:
   - `ulisp/lib/math.scm` に既存の `floor/`, `truncate/` を基底として、負数・境界値・丸め方向を考慮した高効率整数アルゴリズムを実装。
   - ゼロ除算時の `error` 送出。
   - スラッシュ付き手続き（`floor/` 等）は `(values q r)` を返却。

3. **ライブラリの作成**:
   - `ulisp/lib/srfi/141.sld` および `ulisp/lib/scheme/division.sld` を定義。

4. **単体テストの作成**:
   - 正の数、負の数、割り切れる場合、割り切れない場合の全 18 手続きの数学的振る舞いを網羅検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] SRFI 141 規定の全 18 手続きが正確な結果を返す
- [x] 負の除数・被除数に対する境界条件テストがすべて PASS する
- [x] `(srfi 141)` および `(scheme division)` ライブラリとしてインポート可能
- [x] `ref_r7rs_compliance.md` に SRFI 141 の完全準拠（◎）が反映される
- [x] `make test` を通過する
