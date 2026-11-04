---
ID: 732
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] スケジューラ統計における正常完了タスク数と異常終了 (パニック) タスク数の分離計上 (ID: 732)

## 1. 概要 / Summary
現在、`scheduler.scm` の統計カウンタは `tasks-spawned` と `tasks-completed` の2つしかなく、タスクが異常終了（パニック）した場合も正常完了と同じ `completed` として数えられている（項目 A8）。タスク境界が返す結果（正常完了か異常終了か）を見て、スケジューラ統計を「完了（completed）」と「異常終了（failed / panicked）」に分けて計上するようにする。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 7, Section 8.4)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [test_scheduler.scm](../../tests/concurrency/test_scheduler.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/732-separate-completed-and-failed-scheduler-stats`

1. `<work-stealing-scheduler>` の `stats` ベクタに異常終了タスク数用のアトミックカウンタを追加し、`scheduler-tasks-failed` アクセサおよび `scheduler-stats` の `'tasks-failed` 項目を提供する。
2. `%scheduler-run-and-record!` でタスク境界の実行結果を判定し、正常終了時は `completed`、パニック／例外終了時は `failed` をインクリメントする。
3. スケジューラの終了待ち判定では `(+ completed failed)` が `spawned` に達したかで判定する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 正常完了したタスクと異常終了したタスクが `scheduler-tasks-completed` と `scheduler-tasks-failed` に分けて正確に数えられること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

