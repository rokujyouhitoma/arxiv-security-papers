---
ID: 854
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] SRFI 101 純粋関数型ランダムアクセスリスト ((scheme rlist)) の実装 (ID: 854)

## 1. 概要 / Summary
R7RS-large Red Edition に規定される SRFI 101 (Purely Functional Random-Access Pairs and Lists) は、Okasaki の Skew Binary Random-Access Lists に基づき、最悪計算量 $O(1)$ の `cons` / `car` / `cdr` と $O(\log n)$ のランダムアクセス `list-ref` / `list-set` を両立する不変データ構造である。
現状の ULisp では「× (未サポート)」となっている。
本 Issue では、SRFI 101 完全準拠の `(scheme rlist)` および `(srfi 101)` ライブラリを実装し、Red Edition の仕様カバレッジを向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様:
  - R7RS-large Red Edition: `(scheme rlist)`
  - SRFI 101: Purely Functional Random-Access Pairs and Lists
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.1
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/rlist.scm](../../ulisp/lib/rlist.scm) (新規作成)
- [ ] [ulisp/lib/scheme/rlist.sld](../../ulisp/lib/scheme/rlist.sld) (新規作成)
- [ ] [ulisp/lib/srfi/101.sld](../../ulisp/lib/srfi/101.sld) (新規作成)
- [ ] [ulisp/tests/test_srfi_101.scm](../../ulisp/tests/test_srfi_101.scm) (新規作成)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/854-implement-srfi-101-purely-functional-random-access-lists`

1. **データ構造設計**:
   - 完全二分木のフォレスト（Skew Binary 表現）を用いた不変ノード表現。
   - `ra-pair`, `ra-pair?`, `ra-cons`, `ra-car`, `ra-cdr`, `ra-null?`, `ra-list?`。
2. **ランダムアクセス手続き**:
   - `ra-list-ref`, `ra-list-set` を $O(\log n)$ で実装。
   - 高階関数 `ra-map`, `ra-for-each`, `ra-fold`, `ra-unfold`, リスト相互変換 `list->rlist`, `rlist->list` の実装。
3. **テスト検証**:
   - 10,000 要素超のランダムアクセスおよび関数型更新の正当性と計算量特性を SRFI 64 テストスイートで検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(scheme rlist)` および `(srfi 101)` が正常に定義され、エクスポートされること。
- [ ] `ra-cons` が $O(1)$、`ra-list-ref` が $O(\log n)$ で正しく動作すること。
- [ ] `test_srfi_101.scm` が全 PASS すること。
