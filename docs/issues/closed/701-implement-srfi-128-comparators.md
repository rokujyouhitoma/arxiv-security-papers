---
ID: 701
種別: Feature
優先度: High
ステータス: Closed
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
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §3

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/scheme/comparator.sld](../../../ulisp/lib/scheme/comparator.sld) (新規 `(scheme comparator)` ライブラリ定義)
- [x] [ulisp/lib/srfi/128.sld](../../../ulisp/lib/srfi/128.sld) (新規 `(srfi 128)` エイリアス定義)
- [x] [ulisp/lib/comparator.scm](../../../ulisp/lib/comparator.scm) (新規 比較器コア実装)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/comparator.scm` 統合および `test_comparator` ターゲット追加)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`builtin-library-name?` への `comparator`, `128` 追加)
- [x] [ulisp/tests/test_comparator.scm](../../../ulisp/tests/test_comparator.scm) (新規 ユニットテストスイート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/701-implement-srfi-128-comparators`

### Step 1: `<comparator>` レコード型とプリミティブアクセサの定義 (`ulisp/lib/comparator.scm`)
- `define-record-type` により `<comparator>` を定義し、`make-comparator`, `comparator?`, `comparator-ordered?`, `comparator-hashable?`, `comparator-type-test-predicate`, `comparator-equality-predicate`, `comparator-ordering-predicate`, `comparator-hash-function`, `comparator-test-type`, `comparator-check-type`, `comparator-equal?`, `comparator-compare`, `comparator-hash` を実装。

### Step 2: ハッシュ関数群とハッシュ境界条件 (`hash-bound`, `hash-salt`)
- `hash-bound`, `hash-salt`, `boolean-hash`, `char-hash`, `char-ci-hash`, `string-hash`, `string-ci-hash`, `symbol-hash`, `number-hash`, `default-hash` を提供。

### Step 3: コンビネータ比較器とデフォルト比較器の実装
- `make-pair-comparator`, `make-list-comparator`, `make-vector-comparator`, `make-eq-comparator`, `make-eqv-comparator`, `make-equal-comparator`, `make-default-comparator`, `default-comparator`, `comparator-register-default!`, および各プリミティブ型標準比較器を実装。

### Step 4: 比較述語と条件分岐構文
- `=?`, `<?`, `>?`, `<=?`, `>=?` および `comparator-if<=>` 構文を実装。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme comparator)` および `(srfi 128)` ライブラリが定義され、SRFI 128 全標準手続き・構文がエクスポートされていること。
- [x] 標準型（Fixnum、真偽値、文字、文字列、シンボル、ペア、リスト、ベクタ、Bytevector）に対する基本比較器、`default-comparator`、および `=?` / `<?` / `>?` / `<=?` / `>=?` / `comparator-if<=>` が期待通り動作すること。
- [x] `make -C ulisp test_comparator` により AOT ネイティブコンパイル・実行テストが全件 PASS すること。
- [x] `python3 ulisp/scripts/lint_sexpr.py` および `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。

