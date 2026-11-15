---
ID: 853
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 133 ベクタ操作ライブラリおよび (scheme vector) モジュールの完全実装 (ID: 853)

## 1. 概要 / Summary
R7RS-large Red Edition において中核データ構造仕様として定められている SRFI 133 (Vector Library / R7RS-compatible) は、SRFI 43 の改善版であり、ベクタの生成、畳み込み、述語、探索、反転等の包括的な高階関数 API を規定する。
現状の ULisp では `(scheme vector)` の `.sld` や `srfi/133.sld` が存在せず、基本ベクタ関数のみが散在している。
本 Issue では、SRFI 133 に規定される全手続きを実装し、`(srfi 133)` および `(scheme vector)` としてライブラリ提供する。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Red Edition: `(scheme vector)`
  - SRFI 133: Vector Library (R7RS-compatible)
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm)
- [ ] [ulisp/lib/scheme/vector.sld](../../ulisp/lib/scheme/vector.sld) (新規作成)
- [ ] [ulisp/lib/srfi/133.sld](../../ulisp/lib/srfi/133.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_133.scm](../../ulisp/tests/test_srfi_133.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/853-implement-srfi-133-vector-library-and-scheme-vector-module`

1. **Constructors & Predicates**:
   - `make-vector`, `vector`, `vector-unfold`, `vector-unfold-right`, `vector-copy`, `vector-reverse-copy`, `vector-append`, `vector-concatenate`, `vector-append-subvectors`, `vector?`, `vector-empty?`, `vector=`.
2. **Selectors & Iterators**:
   - `vector-ref`, `vector-length`, `vector-fold`, `vector-fold-right`, `vector-map`, `vector-map!`, `vector-for-each`, `vector-count`, `vector-cumulate`.
3. **Searching & Mutators**:
   - `vector-index`, `vector-index-right`, `vector-skip`, `vector-skip-right`, `vector-binary-search`, `vector-any`, `vector-every`, `vector-partition`.
   - `vector-set!`, `vector-swap!`, `vector-fill!`, `vector-reverse!`, `vector-copy!`, `vector-reverse-copy!`.
4. **ライブラリ宣言とテスト**:
   - `(scheme vector)` および `(srfi 133)` を定義し、SRFI 64 テストスイートを作成して網羅的に検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] SRFI 133 の全手続きが実装され、`(scheme vector)` から正常にインポートできること。
- [ ] `vector-fold`, `vector-unfold`, `vector-binary-search` 等の高階関数が正しく動作すること。
- [ ] 新設テスト `test_srfi_133.scm` が全 PASS すること。
