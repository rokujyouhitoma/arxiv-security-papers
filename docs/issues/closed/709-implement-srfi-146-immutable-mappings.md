---
ID: 709
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large Tangerine Edition / SRFI 146 (scheme mapping) 不変マッピングライブラリの実装 (ID: 709)

## 1. 概要 / Summary
R7RS-large Tangerine Edition の最重要純粋関数型データ構造である **SRFI 146 (`(scheme mapping)` / `(srfi 146)` および `(scheme mapping hash)` / `(srfi 146 hash)`)** を実装する。先行実装した SRFI 128 (`(scheme comparator)`) の順序比較述語およびハッシュ関数を基盤として、順序付き不変辞書 (`mapping`) とハッシュベース不変辞書 (`hashmap`) の生成・検索・関数型更新・走査・分割結合・集合演算・比較器統合を完全サポートする。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§2.2 Tangerine Edition)
  - [SRFI 146: Mappings](https://srfi.schemers.org/srfi-146/srfi-146.html)
  - 先行依存: [Issue #701 (SRFI 128 Comparators)](701-implement-srfi-128-comparators.md), [Issue #704 (SRFI 121/158 Generators)](704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mapping.scm](../../../ulisp/lib/mapping.scm) (新規)
- [x] [mapping.sld](../../../ulisp/lib/scheme/mapping.sld) (新規)
- [x] [hash.sld](../../../ulisp/lib/scheme/mapping/hash.sld) (新規)
- [x] [146.sld](../../../ulisp/lib/srfi/146.sld) (新規)
- [x] [hash.sld](../../../ulisp/lib/srfi/146/hash.sld) (新規)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_mapping.scm](../../../ulisp/tests/test_mapping.scm) (新規)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/709-implement-srfi-146-immutable-mappings`

1. **データ構造と内部表現 ([mapping.scm](../../../ulisp/lib/mapping.scm))**:
   - `<mapping>` レコード: `(comparator entries)` — `comparator` の `<` 述語 (`<?`) に従ってキー昇順に整列された不変 `(key . val)` ペアのリストを保持。
   - `<hashmap>` レコード: `(comparator entries)` — `comparator` の等価述語 (`=?`) とハッシュ関数 (`comparator-hash`) に基づく不変 `(key . val)` ペアのコレクションを保持。
2. **`(scheme mapping)` / `(srfi 146)` 全手続きの実装**:
   - コンストラクタ: `mapping`, `mapping-unfold`, `mapping/ordered`, `mapping-unfold/ordered`
   - 述語: `mapping?`, `mapping-contains?`, `mapping-empty?`, `mapping-disjoint?`
   - アクセサ: `mapping-ref`, `mapping-ref/default`, `mapping-key-comparator`
   - 更新器 (純粋版 & 線形更新 `!` 版): `mapping-adjoin`, `mapping-adjoin!`, `mapping-set`, `mapping-set!`, `mapping-replace`, `mapping-replace!`, `mapping-delete`, `mapping-delete!`, `mapping-delete-all`, `mapping-delete-all!`, `mapping-intern`, `mapping-intern!`, `mapping-update`, `mapping-update!`, `mapping-update/default`, `mapping-update!/default`, `mapping-pop`, `mapping-pop!`, `mapping-search`, `mapping-search!`
   - 全体操作: `mapping-size`, `mapping-find`, `mapping-count`, `mapping-any?`, `mapping-every?`, `mapping-keys`, `mapping-values`, `mapping-entries`
   - 写像と畳み込み: `mapping-map`, `mapping-for-each`, `mapping-fold`, `mapping-fold/reverse`, `mapping-map->list`, `mapping-filter`, `mapping-filter!`, `mapping-remove`, `mapping-remove!`, `mapping-partition`, `mapping-partition!`
   - 変換とコピー: `mapping-copy`, `mapping->alist`, `alist->mapping`, `alist->mapping!`, `alist->mapping/ordered`, `alist->mapping/ordered!`
   - 部分マッピングと集合演算: `mapping=?`, `mapping<?`, `mapping>?`, `mapping<=?`, `mapping>=?`, `mapping-union`, `mapping-intersection`, `mapping-difference`, `mapping-xor`, `mapping-union!`, `mapping-intersection!`, `mapping-difference!`, `mapping-xor!`
   - 順序操作 (Ordered Mappings 専用): `mapping-min-key`, `mapping-max-key`, `mapping-min-value`, `mapping-max-value`, `mapping-min-entry`, `mapping-max-entry`, `mapping-key-predecessor`, `mapping-key-successor`, `mapping-range=`, `mapping-range<`, `mapping-range>`, `mapping-range<=`, `mapping-range>=`, `mapping-range=!`, `mapping-range<!`, `mapping-range>!`, `mapping-range<=!`, `mapping-range>=!`, `mapping-split`, `mapping-catenate`, `mapping-catenate!`, `mapping-map/monotone`, `mapping-map/monotone!`
   - 比較器統合: `mapping-comparator`, `make-mapping-comparator`
3. **`(scheme mapping hash)` / `(srfi 146 hash)` 全手続きの実装**:
   - `hashmap`, `hashmap-unfold`, `hashmap?`, `hashmap-contains?`, `hashmap-empty?`, `hashmap-disjoint?`, `hashmap-ref`, `hashmap-ref/default`, `hashmap-key-comparator`, `hashmap-adjoin`, `hashmap-adjoin!`, `hashmap-set`, `hashmap-set!`, `hashmap-replace`, `hashmap-replace!`, `hashmap-delete`, `hashmap-delete!`, `hashmap-delete-all`, `hashmap-delete-all!`, `hashmap-intern`, `hashmap-intern!`, `hashmap-update`, `hashmap-update!`, `hashmap-update/default`, `hashmap-update!/default`, `hashmap-pop`, `hashmap-pop!`, `hashmap-search`, `hashmap-search!`, `hashmap-size`, `hashmap-find`, `hashmap-count`, `hashmap-any?`, `hashmap-every?`, `hashmap-keys`, `hashmap-values`, `hashmap-entries`, `hashmap-map`, `hashmap-for-each`, `hashmap-fold`, `hashmap-map->list`, `hashmap-filter`, `hashmap-filter!`, `hashmap-remove`, `hashmap-remove!`, `hashmap-partition`, `hashmap-partition!`, `hashmap-copy`, `hashmap->alist`, `alist->hashmap`, `alist->hashmap!`, `hashmap=?`, `hashmap<?`, `hashmap>?`, `hashmap<=?`, `hashmap>=?`, `hashmap-union`, `hashmap-intersection`, `hashmap-difference`, `hashmap-xor`, `hashmap-union!`, `hashmap-intersection!`, `hashmap-difference!`, `hashmap-xor!`, `hashmap-comparator`, `make-hashmap-comparator`

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(scheme mapping)` / `(srfi 146)` および `(scheme mapping hash)` / `(srfi 146 hash)` の全手続きが実装され、AOT テスト [test_mapping.scm](../../../ulisp/tests/test_mapping.scm) が exit code 0 で PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) で SRFI 146 (`(scheme mapping)` / `(scheme mapping hash)`) が **◎** に更新されていること。

