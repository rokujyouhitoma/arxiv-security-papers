---
ID: 863
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 214 動的可変長ベクタ ((scheme flexvector)) の実装 (ID: 863)

## 1. 概要 / Summary
R7RS-large Hypnos Docket に規定される SRFI 214 (Flexvectors) は、動的にサイズ拡張・縮小が可能な拡張ベクタ型（動的配列 / std::vector 相当）を規定する。
Scheme 標準の固定長ベクタに対し、末尾への $O(1)$ 償却挿入・削除、任意位置への挿入、スライス操作などを備え、アルゴリズム記述を大幅に簡素化・高速化する。
本 Issue では、SRFI 214 完全準拠の `(scheme flexvector)` および `(srfi 214)` ライブラリを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Hypnos Docket: `(scheme flexvector)`
  - SRFI 214: Flexvectors
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/flexvector.scm](../../ulisp/lib/flexvector.scm) (新規作成)
- [ ] [ulisp/lib/scheme/flexvector.sld](../../ulisp/lib/scheme/flexvector.sld) (新規作成)
- [ ] [ulisp/lib/srfi/214.sld](../../ulisp/lib/srfi/214.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_214.scm](../../ulisp/tests/test_srfi_214.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/863-implement-srfi-214-flexvectors`

1. **データ構造設計**:
   - 内部バッファ（ヒープベクタ）、現在長、容量を管理するレコード構造。
   - 幾何学的倍加（2倍リサイズ）による $O(1)$ 償却計算量の保証。
2. **API 実装**:
   - `make-flexvector`, `flexvector`, `flexvector-ref`, `flexvector-set!`, `flexvector-length`.
   - `flexvector-add-back!`, `flexvector-remove-back!`, `flexvector-add-front!`, `flexvector-remove-front!`.
   - `flexvector-insert!`, `flexvector-delete!`, `flexvector-append!`, `flexvector-copy`.
   - 高階関数: `flexvector-map`, `flexvector-for-each`, `flexvector-fold`, `flexvector-filter!`.
3. **テスト検証**:
   - 多数要素の連続 push/pop による再割り当て整合性とメモリリーク耐性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme flexvector)` / `(srfi 214)` がエクスポートされ利用可能であること。
- [ ] 動的リサイズと要素参照が高速・安全に動作すること。
- [ ] `test_srfi_214.scm` が全 PASS すること。
