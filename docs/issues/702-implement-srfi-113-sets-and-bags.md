---
ID: 702
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large / SRFI 113 (scheme set) 集合およびマルチセット (Bags) データ構造の実装 (ID: 702)

## 1. 概要 / Summary

R7RS-large Red Edition の中核コレクション仕様である **SRFI 113 (Sets and bags)** および標準ライブラリ **`(scheme set)`** を ULisp AOT メタコンパイラ環境に実装する。
SRFI 113 は、要素の重複を許さない集合（Set）および要素の重複度（多重度）を保持するマルチセット（Bag）に対する包括的操作（生成、所属判定、要素追加・削除、和集合、積集合、差集合、対称差、部分集合判定等）を提供する。
実用的な Scheme アプリケーション、CTI 脅威分析、オントロジー因果追跡、およびコンパイラ最適化における変数集合演算の共通基盤となる。

---

## 2. トレーサビリティ / Traceability

- 関連仕様:
  - R7RS-large Red Edition: [RedEdition.md](https://github.com/johnwcowan/r7rs-work/blob/master/RedEdition.md)
  - SRFI 113 正典仕様書: [SRFI 113: Sets and bags](https://srfi.schemers.org/srfi-113/srfi-113.html)
  - 前提 Issue: [Issue #701](701-implement-srfi-128-comparators.md) (SRFI 128 Comparators)
  - ULisp 言語仕様準拠リファレンス: [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/scheme/set.sld](../../ulisp/lib/scheme/set.sld) (新規 `(scheme set)` ライブラリ定義)
- [ ] [ulisp/lib/srfi/113.sld](../../ulisp/lib/srfi/113.sld) (新規 `(srfi 113)` エイリアス定義)
- [ ] [ulisp/lib/set.scm](../../ulisp/lib/set.scm) (新規 集合およびマルチセット実装)
- [ ] [ulisp/tests/test_set.scm](../../ulisp/tests/test_set.scm) (新規 ユニットテストスイート)
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (ステータス更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/702-implement-srfi-113-sets-and-bags`

1. **データ構造設計**:
   - `define-record-type` により `<set>` 型および `<bag>` 型を定義し、比較器 (Comparator) インスタンスおよび内部ストレージ（ハッシュテーブル / 平衡連想リスト）を保持。
2. **集合操作の実装 (Sets)**:
   - `set`, `set-unfold`, `set?`, `set-contains?`, `set-empty?`, `set-disjoint?`
   - `set-member`, `set-element-comparator`
   - `set-adjoin`, `set-adjoin!`, `set-replace`, `set-replace!`, `set-delete`, `set-delete!`
   - `set-size`, `set-find`, `set-count`, `set-any?`, `set-every?`
   - `set-map`, `set-for-each`, `set-fold`, `set-filter`, `set-remove`, `set-partition`
   - `set-copy`, `set->list`, `list->set`, `list->set!`
   - `set=?`, `set<?`, `set<=?`, `set>?`, `set>=?`
   - `set-union`, `set-intersection`, `set-difference`, `set-xor` (および線形破壊的 `*!` バージョン)
3. **マルチセット操作の実装 (Bags)**:
   - `bag`, `bag?`, `bag-contains?`, `bag-count`, `bag-adjoin`, `bag-delete`, `bag-sum`, `bag-product`, `bag-intersection`, `bag-difference` 等。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(scheme set)` および `(srfi 113)` ライブラリが定義され、全標準手続きがエクスポートされていること。
- [ ] 集合の構築、基本操作、集合代数演算（和・積・差）、およびマルチセット多重度管理のテストケースが網羅されていること。
- [ ] AOT ネイティブコンパイルおよび Portable C バックエンドの両方で回帰テストが PASS すること。
- [ ] `make verify_r7rs_traceability` が 100% PASS し、`ref_r7rs_compliance.md` のステータスが **◎** に更新されること。
