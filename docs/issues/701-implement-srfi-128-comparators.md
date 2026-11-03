---
ID: 701
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 128 (scheme comparator) 第一級比較器ライブラリの実装 (ID: 701)

## 1. 概要 / Summary

R7RS-large Red Edition の最重要共通基盤仕様である **SRFI 128 (Comparators: reduced)** および標準ライブラリ **`(scheme comparator)`** を ULisp AOT メタコンパイラ環境に実装する。
SRFI 128 は、データ型の型検査述語 (`type-test`)、等価性述語 (`equality`)、順序比較述語 (`ordering`)、ハッシュ計算関数 (`hash`) の 4 つの要素をカプセル化する第一級比較器 (Comparator) オブジェクトを提供する。
本機能は、後続の SRFI 113 (Sets and Bags)、SRFI 125 (ハッシュテーブル高度機能)、SRFI 146 (不変マッピング) 等のすべてのコレクションライブラリの前提条件（Keystone）となる。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Red Edition: [RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
  - SRFI 128 正典仕様書: [SRFI 128: Comparators (reduced)](https://srfi.schemers.org/srfi-128/srfi-128.html)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/scheme/comparator.sld](../../ulisp/lib/scheme/comparator.sld) (新規 `(scheme comparator)` ライブラリ定義)
- [ ] [ulisp/lib/srfi/128.sld](../../ulisp/lib/srfi/128.sld) (新規 `(srfi 128)` エイリアス定義)
- [ ] [ulisp/lib/comparator.scm](../../ulisp/lib/comparator.scm) (新規 比較器コア実装)
- [ ] [ulisp/tests/test_comparator.scm](../../ulisp/tests/test_comparator.scm) (新規 ユニットテストスイート)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/701-implement-srfi-128-comparators`

1. **レコード型による比較器表現**:
   - `define-record-type` を用い、型述語・等価述語・順序述語・ハッシュ関数・一意タグを保持する `<comparator>` 型を定義。
2. **標準コンパレータの提供**:
   - `boolean-comparator`, `char-comparator`, `char-ci-comparator`, `string-comparator`, `string-ci-comparator`, `symbol-comparator`, `exact-integer-comparator`, `default-comparator` 等の組み込み比較器の初期化。
3. **高階コンビネータとアクセス手続き**:
   - `make-comparator`, `make-pair-comparator`, `make-list-comparator`, `make-vector-comparator`
   - `comparator?`, `comparator-ordered?`, `comparator-hashable?`
   - `comparator-test-type`, `comparator-check-type`, `comparator-equal?`, `comparator-compare`, `comparator-hash`
   - `=?`, `<?`, `>?`, `<=`, `>=` 等の比較器駆動比較述語。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(scheme comparator)` および `(srfi 128)` ライブラリが定義され、全標準手続きがエクスポートされていること。
- [ ] 標準型（Fixnum、真偽値、文字、文字列、シンボル、ペア、ベクタ）に対する基本コンパレータおよび比較マクロが期待通り動作すること。
- [ ] AOT ネイティブコンパイル (x86-64 / AArch64) および Portable C バックエンドの両方で回帰テストが PASS すること。
- [ ] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。

