---
ID: 710
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 116 (scheme ilist) 不変リストおよび SRFI 134 (scheme ideque) 不変両端キューの実装 (ID: 710)

## 1. 概要 / Summary
R7RS-large Red Edition の純粋関数型シーケンスデータ構造である **SRFI 116 (`(scheme ilist)` / `(srfi 116)` Immutable Pairs and Lists)** および **SRFI 134 (`(scheme ideque)` / `(srfi 134)` Immutable Deques)** を実装する。タグ付き不変ペア型 (`ipair`) とその上の SRFI 1 互換高階操作群、ならびに償却 $O(1)$ 両端操作を提供する Banker's Deque (`ideque`) を実装し、Red Edition 準拠率を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 116: Immutable Pairs and Lists](https://srfi.schemers.org/srfi-116/srfi-116.html)
  - [SRFI 134: Immutable Deques](https://srfi.schemers.org/srfi-134/srfi-134.html)
  - 先行依存: [Issue #701 (SRFI 128 Comparators)](701-implement-srfi-128-comparators.md), [Issue #704 (SRFI 121/158 Generators)](704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ilist.scm](../../../ulisp/lib/ilist.scm) (新規)
- [x] [ideque.scm](../../../ulisp/lib/ideque.scm) (新規)
- [x] [ilist.sld](../../../ulisp/lib/scheme/ilist.sld) (新規)
- [x] [116.sld](../../../ulisp/lib/srfi/116.sld) (新規)
- [x] [ideque.sld](../../../ulisp/lib/scheme/ideque.sld) (新規)
- [x] [134.sld](../../../ulisp/lib/srfi/134.sld) (新規)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_ilist_ideque.scm](../../../ulisp/tests/test_ilist_ideque.scm) (新規)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques`

1. **SRFI 116 (`(scheme ilist)` / `(srfi 116)`) の実装 ([ilist.scm](../../../ulisp/lib/ilist.scm))**:
   - `<ipair>` レコード（または `#(ulisp-ipair-tag <icar> <icdr>)`）による可変ペア `pair?` と互いに素な不変ペア型: `ipair`, `ipair?`, `icar`, `icdr`.
   - コンストラクタ: `ilist`, `xipair`, `ipair*`, `make-ilist`, `ilist-tabulate`, `iiota`, `ilist-copy`.
   - 述語: `proper-ilist?`, `ilist?`, `dotted-ilist?`, `not-ipair?`, `null-ilist?`, `ilist=`.
   - セレクタ: `icaar`〜`icddddr` (全 28 種の c*r アクセサ), `ilist-ref`, `ifirst`〜`itenth`, `icar+icdr`, `itake`, `idrop`, `ilist-tail`, `itake-right`, `idrop-right`, `isplit-at`, `ilast`, `last-ipair`.
   - 長さ・結合・反転・zip: `ilength`, `iappend`, `iconcatenate`, `ireverse`, `iappend-reverse`, `izip`, `iunzip1`〜`iunzip5`, `icount`.
   - 畳み込み・写像・フィルタ・探索・削除・連想リスト: `ifold`, `iunfold`, `ipair-fold`, `ireduce`, `ifold-right`, `iunfold-right`, `ipair-fold-right`, `ireduce-right`, `iappend-map`, `ipair-for-each`, `ifilter-map`, `imap-in-order`, `imap`, `ifor-each`, `ifilter`, `ipartition`, `iremove`, `ifind`, `ifind-tail`, `itake-while`, `idrop-while`, `ispan`, `ibreak`, `iany`, `ievery`, `ilist-index`, `imember`, `imemq`, `imemv`, `idelete`, `idelete-duplicates`, `iassoc`, `iassq`, `iassv`, `ialist-cons`, `ialist-delete`.
   - 置換・相互変換・比較器: `replace-icar`, `replace-icdr`, `pair->ipair`, `ipair->pair`, `list->ilist`, `ilist->list`, `tree->itree`, `itree->tree`, `gtree->itree`, `gtree->tree`, `iapply`, `ipair-comparator`, `ilist-comparator`, `make-ilist-comparator`, `make-improper-ilist-comparator`, `make-ipair-comparator`, `make-icar-comparator`, `make-icdr-comparator`.
2. **SRFI 134 (`(scheme ideque)` / `(srfi 134)`) の実装 ([ideque.scm](../../../ulisp/lib/ideque.scm))**:
   - Banker's Deque `(front-len front-list back-len back-list)` による不変両端キュー。
   - コンストラクタ・変換: `ideque`, `ideque-tabulate`, `ideque-unfold`, `ideque-unfold-right`, `list->ideque`, `ideque->list`, `generator->ideque`, `ideque->generator`.
   - 述語: `ideque?`, `ideque-empty?`, `ideque=`, `ideque-any`, `ideque-every`.
   - キュー操作: `ideque-front`, `ideque-back`, `ideque-remove-front`, `ideque-remove-back`, `ideque-add-front`, `ideque-add-back`, `ideque-ref`, `ideque-take`, `ideque-take-right`, `ideque-drop`, `ideque-drop-right`, `ideque-split-at`.
   - 全体操作・高階操作: `ideque-length`, `ideque-append`, `ideque-reverse`, `ideque-count`, `ideque-zip`, `ideque-map`, `ideque-filter-map`, `ideque-for-each`, `ideque-for-each-right`, `ideque-fold`, `ideque-fold-right`, `ideque-append-map`, `ideque-filter`, `ideque-remove`, `ideque-partition`, `ideque-find`, `ideque-find-right`, `ideque-take-while`, `ideque-take-while-right`, `ideque-drop-while`, `ideque-drop-while-right`, `ideque-span`, `ideque-break`.

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(scheme ilist)` / `(srfi 116)` および `(scheme ideque)` / `(srfi 134)` の全手続きが実装され、AOT テスト [test_ilist_ideque.scm](../../../ulisp/tests/test_ilist_ideque.scm) が exit code 0 で PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) で SRFI 116 (`(scheme ilist)`) および SRFI 134 (`(scheme ideque)`) が **◎** に更新されていること。

