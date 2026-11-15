---
ID: 857
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 151 ビット演算包括ライブラリおよび (scheme bitwise) の実装 (ID: 857)

## 1. 概要 / Summary
R7RS-large Tangerine Edition においてビット操作の標準仕様とされている SRFI 151 (Bitwise Operations) は、整数の2進ビット表現に対する包括的演算手続き群を規定する。
ULisp では `bitwise-and`, `bitwise-ior`, `bitwise-arithmetic-shift` 等の基本プリミティブがコンパイラ内に点在しているのみで、ライブラリとしての `(scheme bitwise)` や `(srfi 151)` が存在しない。
本 Issue では、SRFI 151 規定の全 60 余の手続きを実装し、完全なビット演算ライブラリを提供する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Tangerine Edition: `(scheme bitwise)`
  - SRFI 151: Bitwise Operations
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.2
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/bitwise.scm](../../ulisp/lib/bitwise.scm) (新規作成)
- [ ] [ulisp/lib/scheme/bitwise.sld](../../ulisp/lib/scheme/bitwise.sld) (新規作成)
- [ ] [ulisp/lib/srfi/151.sld](../../ulisp/lib/srfi/151.sld) (新規作成)
- [ ] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm)
- [ ] [ulisp/tests/test_srfi_151.scm](../../ulisp/tests/test_srfi_151.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/857-implement-srfi-151-bitwise-operations-and-scheme-bitwise`

1. **基本ブール論理手続き**:
   - `bitwise-not`, `bitwise-and`, `bitwise-ior`, `bitwise-xor`, `bitwise-eqv`, `bitwise-nand`, `bitwise-nor`, `bitwise-andc1`, `bitwise-andc2`, `bitwise-orc1`, `bitwise-orc2`.
2. **ビットシフト・計数・フィールド操作**:
   - `arithmetic-shift`, `bit-count`, `integer-length`, `bitwise-if`, `bit-set?`, `copy-bit`, `first-set-bit`.
   - `bit-field`, `bit-field-any?`, `bit-field-every?`, `bit-field-clear`, `bit-field-set`, `bit-field-replace`, `bit-field-copy`.
3. **ビット単位の畳み込み・反復**:
   - `bitwise-fold`, `bitwise-for-each`, `bitwise-unfold`, `make-bitwise-generator`.
4. **テストスイート**:
   - SRFI 151 公式リファレンステストに基づく検証テストスイートを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme bitwise)` および `(srfi 151)` から全手続きがインポート可能であること。
- [ ] 負数（2の補数表現）および 62-bit Fixnum の全範囲でビット演算が正しく動作すること。
- [ ] `test_srfi_151.scm` が全 PASS すること。
