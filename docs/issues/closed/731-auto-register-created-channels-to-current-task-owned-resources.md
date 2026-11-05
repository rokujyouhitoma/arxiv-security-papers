---
ID: 731
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] make-channel 実行時における現在タスク所有チャネル一覧への自動登録 (ID: 731)

## 1. 概要 / Summary
現在、`<task-context>` には所有チャネル一覧 `owned-channels-box` と `task-register-channel!` が用意されているが、`make-channel`（および `make-spsc-channel`）を呼び出した際に現在のタスクへ自動で登録されていない（項目 A6）。`make-channel` 実行時に `current-synapse-task` が存在する場合は自動で `task-register-channel!` を行い、タスク異常終了時の自動チャネル毒化（Channel Poisoning）が漏れなく機能するようにする。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4.2)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [x] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [x] [test_channel.scm](../../tests/concurrency/test_channel.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/731-auto-register-channel-on-creation`

1. `%make-channel-instance`（`make-channel` / `make-spsc-channel` の共通生成部）で、実行中のタスク（`current-synapse-task`）が存在する場合に `task-register-channel!` を自動実行する。
2. `channel-close!` 時に所有リストから外す連携も整理する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] タスク境界内で `make-channel` を呼ぶだけで、手動の `task-register-channel!` なしに現在タスクの `task-owned-channels` に自動登録されること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

