---
ID: 710
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] R7RS-large Red Edition / SRFI 116 (scheme ilist) 不変リストおよび SRFI 134 (scheme ideque) 不変両端キューの実装 (ID: 710)

## 1. 概要 / Summary
R7RS-large Red Edition の純粋関数型シーケンスデータ構造である **SRFI 116 (`(scheme ilist)` / `(srfi 116)` Immutable Pairs and Lists)** および **SRFI 134 (`(scheme ideque)` / `(srfi 134)` Immutable Deques)** を実装する。タグ付き不変ペア型 (`ipair`) とその上の SRFI 1 互換高階操作群、ならびに償却 $O(1)$ 両端操作を提供する Banker's Deque (`ideque`) を実装し、Red Edition 準拠率を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability
- 関連資料:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) (§2.1 Red Edition)
  - [SRFI 116: Immutable Pairs and Lists](https://srfi.schemers.org/srfi-116/srfi-116.html)
  - [SRFI 134: Immutable Deques](https://srfi.schemers.org/srfi-134/srfi-134.html)
  - 先行依存: [Issue #701 (SRFI 128 Comparators)](closed/701-implement-srfi-128-comparators.md), [Issue #704 (SRFI 121/158 Generators)](closed/704-implement-srfi-158-generators-and-accumulators.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ilist.scm](../../ulisp/lib/ilist.scm) (新規)
- [ ] [ideque.scm](../../ulisp/lib/ideque.scm) (新規)
- [ ] [ilist.sld](../../ulisp/lib/scheme/ilist.sld) (新規)
- [ ] [116.sld](../../ulisp/lib/srfi/116.sld) (新規)
- [ ] [ideque.sld](../../ulisp/lib/scheme/ideque.sld) (新規)
- [ ] [134.sld](../../ulisp/lib/srfi/134.sld) (新規)
- [ ] [helpers.scm](../../ulisp/compiler/helpers.scm)
- [ ] [Makefile](../../ulisp/Makefile)
- [ ] [test_ilist_ideque.scm](../../ulisp/tests/test_ilist_ideque.scm) (新規)
- [ ] [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/710-implement-srfi-116-immutable-lists-and-srfi-134-immutable-deques`

1. `polish-issue` フェーズにて詳細設計および DoD を確定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `polish-issue` により実装仕様・境界条件・テスト計画が定義されていること。

