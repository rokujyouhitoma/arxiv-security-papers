---
ID: 733
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Task ID (TID) からタスクコンテキストを O(1) 解決するロックフリータスク表の実装 (ID: 733)

## 1. 概要 / Summary
現在、Task ID（`tid`）から `<task-context>` を引くための共通のタスク表が存在しない（項目 B2）。ID からタスクを高速・スレッドセーフに引けるロックフリーなタスク表（Task Table）を実装し、タスクの生成・終了ライフサイクルおよび Supervisor / シグナル配送と連携させる。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 6.1, Section 8.4)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [x] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [x] [channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld)
- [x] [test_channel.scm](../../tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/733-implement-task-table`

1. 64 バケットの Lock-Free Atomic Hash Table によるタスク表（`task-table-register!`, `task-table-unregister!, `task-by-id` / `lookup-task-by-tid`）を実装する。
2. `make-task-context` 時に自動登録し、タスク終了時（`task-handle-termination!`）に自動解除する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `tid` から生存中の `<task-context>` を O(1) で取得でき、終了したタスクは表から外れること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

