---
ID: 707
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 117 (scheme list-queue) および SRFI 127 (scheme lseq) の実装 (ID: 707)

## 1. 概要 / Summary
R7RS-large Red Edition (Data Structures & Algorithms) の準拠率を向上させるため、リストベースの $O(1)$ 両端キューを提供する **SRFI 117 (`(scheme list-queue)` / `(srfi 117)`)** と、先行実装した SRFI 121/158 ジェネレータを末尾に持つ遅延シーケンス **SRFI 127 (`(scheme lseq)` / `(srfi 127)`)** を完全実装し、コンプライアンス表の 2 ライブラリを **◎（完全サポート）** に引き上げる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 117: Queues based on lists](https://srfi.schemers.org/srfi-117/srfi-117.html)
  - [SRFI 127: Lazy Sequences](https://srfi.schemers.org/srfi-127/srfi-127.html)
  - 先行依存: [Issue #704 (SRFI 121/158 Generators)](closed/704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [list-queue.scm](../../ulisp/lib/list-queue.scm) (新規)
- [ ] [lseq.scm](../../ulisp/lib/lseq.scm) (新規)
- [ ] [list-queue.sld](../../ulisp/lib/scheme/list-queue.sld) (新規)
- [ ] [117.sld](../../ulisp/lib/srfi/117.sld) (新規)
- [ ] [lseq.sld](../../ulisp/lib/scheme/lseq.sld) (新規)
- [ ] [127.sld](../../ulisp/lib/srfi/127.sld) (新規)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_list_queue_lseq.scm](../../ulisp/tests/test_list_queue_lseq.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/707-implement-srfi-117-list-queues-and-srfi-127-lazy-sequences`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

