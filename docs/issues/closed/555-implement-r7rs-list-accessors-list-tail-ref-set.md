---
ID: 555
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT] R7RS リスト要素アクセス・更新手続き (list-tail / list-ref / list-set!) の実装 (ID: 555)

## 1. 概要 / Summary
R7RS 6.4 (Pairs and lists) に規定されているリスト走査・参照・破壊的更新手続きである `list-tail`, `list-ref`, `list-set!` を `ulisp/lib/list.scm` に実装する。
ULisp のランタイムには既に `set-car!` / `set-cdr!` などのプリミティブが備わっているため、これらを組み合わせて純粋 Scheme 手続きとして安全かつ高速に提供し、標準適合性を向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連仕様: R7RS-small Section 6.4 (Pairs and lists)
  - `(list-tail list k)`: 先頭から k 個のペアをスキップした残りのリスト（または部分リスト）を返す。
  - `(list-ref list k)`: リストの k 番目の要素（0-indexed）を返す (`(car (list-tail list k))` と同等）。
  - `(list-set! list k obj)`: リストの k 番目のペアの car を obj に破壊的代入する。
- 関連ドキュメント: [r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/list.scm](../../ulisp/lib/list.scm) (`list-tail`, `list-ref`, `list-set!` 実装)
- [x] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (単体テストケース追加)
- [x] [ulisp/docs/r7rs_specification_compliance.md](../../ulisp/docs/r7rs_specification_compliance.md) (適合状況更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/555-implement-r7rs-list-accessors-list-tail-ref-set`

1. `ulisp/lib/list.scm` への手続き追加:
   - `list-tail`: 引数 `lst`, `k` を受け取り、末尾再帰で `k` 回 `cdr` を適用。`k = 0` ならば `lst` を返す。範囲外の場合はエラーまたは適切な例外処理。
   - `list-ref`: `(car (list-tail lst k))` を呼び出して要素を取得。
   - `list-set!`: `(set-car! (list-tail lst k) obj)` を呼び出して指定位置の `car` を更新。
2. `ulisp/tests/test_stdlib_r7rs.scm` への網羅テスト追加:
   - 0 番目要素の参照・更新、中間要素、末尾要素の取得検証。
   - `list-set!` 実行後の元リストの破壊的変更の確認。
3. `make -C ulisp test_stdlib` および `./test.sh` によるビルド・テスト検証。
4. `ulisp/docs/r7rs_specification_compliance.md` の該当行のステータスを `[x]` に更新。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `list-tail`, `list-ref`, `list-set!` が `ulisp/lib/list.scm` に実装されていること。
- [x] `tests/test_stdlib_r7rs.scm` で全テストが合格すること。
- [x] `./test.sh` および `./test_c.sh` がエラーなく 100% PASS すること。
- [x] `ulisp/docs/r7rs_specification_compliance.md` のチェックリストが更新されていること。
