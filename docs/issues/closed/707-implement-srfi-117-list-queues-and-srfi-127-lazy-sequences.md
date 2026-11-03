---
ID: 707
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 117 (scheme list-queue) および SRFI 127 (scheme lseq) の実装 (ID: 707)

## 1. 概要 / Summary
R7RS-large Red Edition (Data Structures & Algorithms) の準拠率を向上させるため、リストベースの $O(1)$ 両端キューを提供する **SRFI 117 (`(scheme list-queue)` / `(srfi 117)`)** と、先行実装した SRFI 121/158 ジェネレータを末尾に持つ遅延シーケンス **SRFI 127 (`(scheme lseq)` / `(srfi 127)`)** を完全実装し、コンプライアンス表の 2 ライブラリを **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 117: Queues based on lists](https://srfi.schemers.org/srfi-117/srfi-117.html)
  - [SRFI 127: Lazy Sequences](https://srfi.schemers.org/srfi-127/srfi-127.html)
  - 先行依存: [Issue #704 (SRFI 121/158 Generators)](704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [list-queue.scm](../../../ulisp/lib/list-queue.scm) (新規)
- [x] [lseq.scm](../../../ulisp/lib/lseq.scm) (新規)
- [x] [list-queue.sld](../../../ulisp/lib/scheme/list-queue.sld) (新規)
- [x] [117.sld](../../../ulisp/lib/srfi/117.sld) (新規)
- [x] [lseq.sld](../../../ulisp/lib/scheme/lseq.sld) (新規)
- [x] [127.sld](../../../ulisp/lib/srfi/127.sld) (新規)
- [x] [posix.scm](../../../ulisp/lib/posix.scm)
- [x] [helpers.scm](../../../ulisp/compiler/helpers.scm)
- [x] [Makefile](../../../ulisp/Makefile)
- [x] [test_list_queue_lseq.scm](../../../ulisp/tests/test_list_queue_lseq.scm) (新規)
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/707-implement-srfi-117-list-queues-and-srfi-127-lazy-sequences`

1. **SRFI 117 (`(scheme list-queue)` / `(srfi 117)`) の実装 ([list-queue.scm](../../../ulisp/lib/list-queue.scm))**:
   - 3要素タグ付きベクタ `#(ulisp-list-queue-tag <first-list> <last-pair>)` により tconc 構造を表現し、2引数ヘルパ `%lq-set-first!`, `%lq-set-last!`, `%lq-set-cdr!` で GC ライトバリア安全に更新する。
   - コンストラクタ (`make-list-queue`, `list-queue`, `list-queue-copy`, `list-queue-unfold`, `list-queue-unfold-right`)、述語 (`list-queue?`, `list-queue-empty?`)、アクセサ (`list-queue-front`, `list-queue-back`, `list-queue-list`, `list-queue-first-last`)、ミューテータ (`list-queue-add-front!`, `list-queue-add-back!`, `list-queue-remove-front!`, `list-queue-remove-back!`, `list-queue-remove-all!`, `list-queue-set-list!`)、連結 (`list-queue-append`, `list-queue-append!`, `list-queue-concatenate`)、写像 (`list-queue-map`, `list-queue-map!`, `list-queue-for-each`) をすべて実装する。
2. **SRFI 127 (`(scheme lseq)` / `(srfi 127)`) の実装 ([lseq.scm](../../../ulisp/lib/lseq.scm))**:
   - `generator->lseq`: ジェネレータ `g` から 1 要素を先行取得し、`(eof-object? v)` なら `'()`、そうでなければ `(cons v g)` を返す。
   - `lseq-cdr`: ペアの `cdr` が手続き `g` である場合、`(g)` を呼び出して `(eof-object? v)` なら `'()`、そうでなければ `(cons v g)` で `set-cdr!` してメモ化する。
   - 全標準手続き (`generator->lseq`, `lseq?`, `lseq=?`, `lseq-car`, `lseq-first`, `lseq-cdr`, `lseq-rest`, `lseq-ref`, `lseq-take`, `lseq-drop`, `lseq-realize`, `lseq->generator`, `lseq-length`, `lseq-append`, `lseq-zip`, `lseq-map`, `lseq-for-each`, `lseq-filter`, `lseq-remove`, `lseq-find`, `lseq-find-tail`, `lseq-take-while`, `lseq-drop-while`, `lseq-any`, `lseq-every`, `lseq-index`, `lseq-member`, `lseq-memq`, `lseq-memv`) を実装する。
3. **ライブラリ定義・コンパイラ登録・テスト**:
   - `(scheme list-queue)`, `(srfi 117)`, `(scheme lseq)`, `(srfi 127)` の `.sld` ファイルを作成し、`builtin-library-name?` および `features` に登録する。
   - [test_list_queue_lseq.scm](../../../ulisp/tests/test_list_queue_lseq.scm) を作成し、AOT コンパイル・実行で全 API を検証する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] SRFI 117 全 21 手続きおよび SRFI 127 全 29 手続きが実装され、AOT テスト [test_list_queue_lseq.scm](../../../ulisp/tests/test_list_queue_lseq.scm) が exit code 0 で PASS すること。
- [x] `make -C ulisp lint_sexpr test_r7rs_traceability` が 100% PASS すること。
- [x] [ref_r7rs_compliance.md](../../../ulisp/docs/ref_r7rs_compliance.md) で SRFI 117 (`(scheme list-queue)`) および SRFI 127 (`(scheme lseq)`) が **◎** に更新されていること。

