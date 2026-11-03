---
ID: 702
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large / SRFI 113 (scheme set) 集合およびマルチセット (Bags) データ構造の実装 (ID: 702)

## 1. 概要 / Summary

R7RS-large Red Edition の中核コレクション仕様である **SRFI 113 (Sets and bags)** および標準ライブラリ **`(scheme set)`** を ULisp AOT メタコンパイラ環境に実装する。
SRFI 113 は、要素の重複を許さない集合（Set）および要素の重複度（多重度）を保持するマルチセット（Bag）に対する包括的操作（生成、所属判定、要素追加・削除、和集合、積集合、差集合、対称差、部分集合判定等）を提供する。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Red Edition: [RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
  - SRFI 113 正典仕様書: [SRFI 113: Sets and bags](https://srfi.schemers.org/srfi-113/srfi-113.html)
  - 前提 Issue: [Issue #701](701-implement-srfi-128-comparators.md) (SRFI 128 Comparators)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) §2.1, §3

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lib/scheme/set.sld](../../../ulisp/lib/scheme/set.sld) (新規 `(scheme set)` ライブラリ定義)
- [x] [ulisp/lib/srfi/113.sld](../../../ulisp/lib/srfi/113.sld) (新規 `(srfi 113)` エイリアス定義)
- [x] [ulisp/lib/set.scm](../../../ulisp/lib/set.scm) (新規 集合およびマルチセット実装)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (`ULISP_STD_LIBS` への `lib/set.scm` 統合および `test_set` ターゲット追加)
- [x] [ulisp/compiler/helpers.scm](../../../ulisp/compiler/helpers.scm) (`builtin-library-name?` への `set`, `113` 追加)
- [x] [ulisp/tests/test_set.scm](../../../ulisp/tests/test_set.scm) (新規 ユニットテストスイート)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/702-implement-srfi-113-sets-and-bags`

### Step 1: `<set>` および `<bag>` レコード型の設計 (`ulisp/lib/set.scm`)
- SRFI 128 の `comparator` を要素比較・型検証の核として利用し、内部表現として `(element . count)` の連想リストを保持する `<set>` および `<bag>` レコード型を定義。

### Step 2: Set 手続き群の完全実装
- コンストラクタ・述語・アクセサ・更新器（純粋関数版および線形更新 `*!` 版）、高階イテレータ、コピー・変換、部分集合判定 (`set=?`, `set<?`, `set>?`, `set<=?`, `set>=?`)、および集合代数演算 (`set-union`, `set-intersection`, `set-difference`, `set-xor`) を実装。

### Step 3: Bag (マルチセット) 手続き群の完全実装
- 多重度管理 (`bag-element-count`, `bag-increment!`, `bag-decrement!`)、ユニーク要素走査 (`bag-for-each-unique`, `bag-fold-unique`)、Set / Alist 相互変換、およびマルチセット代数演算 (`bag-union`, `bag-intersection`, `bag-difference`, `bag-xor`, `bag-sum`, `bag-product`) を実装。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `(scheme set)` および `(srfi 113)` ライブラリが定義され、SRFI 113 の Set / Bag 全標準手続きがエクスポートされていること。
- [x] 集合の構築、基本操作、`set-search!`、集合代数演算（和・積・差・対称差）、およびマルチセット多重度管理・相互変換のテストケースが PASS すること。
- [x] `make -C ulisp test_set` により AOT ネイティブコンパイル・実行テストが全件 PASS すること。
- [x] `python3 ulisp/scripts/lint_sexpr.py` および `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。

