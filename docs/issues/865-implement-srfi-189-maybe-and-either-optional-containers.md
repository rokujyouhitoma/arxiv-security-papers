---
ID: 865
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 189 Maybe and Either オプショナルコンテナ ((scheme maybe)) の実装 (ID: 865)

## 1. 概要 / Summary
R7RS-large Hypnos Docket に規定される SRFI 189 (Maybe and Either: optional values and error containers) は、関数型プログラミングにおける失敗の可能性がある計算や選択肢をカプセル化するモナド風コンテナ `Maybe` (`Just` / `Nothing`) および `Either` (`Right` / `Left`) を規定する。
例外を伴わない型安全なエラーハンドリングや値の存在表現を統一的に扱うために不可欠な標準ライブラリである。
現状の ULisp では「× (未サポート)」となっている。
本 Issue では、SRFI 189 完全準拠の `(scheme maybe)` および `(srfi 189)` を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Hypnos Docket: `(scheme maybe)`
  - SRFI 189: Maybe and Either: optional values and error containers
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/maybe.scm](../../ulisp/lib/maybe.scm) (新規作成)
- [ ] [ulisp/lib/scheme/maybe.sld](../../ulisp/lib/scheme/maybe.sld) (新規作成)
- [ ] [ulisp/lib/srfi/189.sld](../../ulisp/lib/srfi/189.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_189.scm](../../ulisp/tests/test_srfi_189.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/865-implement-srfi-189-maybe-and-either-optional-containers`

1. **Constructors & Predicates**:
   - `just`, `nothing`, `maybe?`, `just?`, `nothing?`, `maybe=`.
   - `right`, `left`, `either?`, `right?`, `left?`, `either=`.
2. **Accessors & Unpackers**:
   - `maybe-ref`, `maybe-ref/default`, `either-ref`, `either-ref/default`.
3. **Mappers & Monadic Combinators**:
   - `maybe-map`, `maybe-bind`, `maybe-filter`, `maybe-sequence`.
   - `either-map`, `either-bind`, `either-swap`.
4. **相互変換**:
   - `list->maybe`, `maybe->list`, `boolean->maybe`, `either->maybe`.
5. **テスト検証**:
   - モナド則、短絡評価、デフォルト値フォールバックの正当性を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme maybe)` / `(srfi 189)` が定義され、すべての手続きがエクスポートされること。
- [ ] `Just`, `Nothing`, `Right`, `Left` の値生成とバインド操作が正常に動作すること。
- [ ] `test_srfi_189.scm` が全 PASS すること。
