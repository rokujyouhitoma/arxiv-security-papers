---
ID: 734
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 4種類のタスク表現の <task-context> への一元化 (ID: 734)

## 1. 概要 / Summary
現在、Synapse ランタイム内には `<task-context>`（`channel.scm`）、`<budgeted-task>`（`preempt.scm`）、`<coroutine-context>`（`context.scm`）、および生の `procedure`（thunk）という4種類のタスク表現が並存しており、`scheduler-execute-task!` 等で毎回分岐処理している（項目 A7）。これら4種類のタスク表現を `<task-context>` 1つに統一し、すべてのタスクが一貫してリダクション管理・例外境界・リンク／監視・アリーナを持てるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 6.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [preempt.scm](../../ulisp/runtime/concurrency/preempt.scm)
- [x] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [x] [test_scheduler.scm](../../tests/concurrency/test_scheduler.scm)
- [x] [test_preemption.scm](../../tests/concurrency/test_preemption.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/734-unify-task-context-representation`

1. `preempt.scm`:
   - `task-id`, `task-target-obj`, `task-exhaustion-count`, `task-consume-reductions!`, `task-replenish!`, `scheduler-yield!`, `budgeted-task-stats` を `<task-context>` に対応させ、`<task-context>` をファーストクラスのプリエンプティブタスクとして扱えるようにする。
2. `scheduler.scm`:
   - `%normalize-task-context` を導入し、`scheduler-spawn!` で受け取る任意のタスク表現（procedure, coroutine-context, budgeted-task, task-context）をすべて標準 `<task-context>` に正規化してキューイングする。
   - `scheduler-execute-task!` を `<task-context>` 実行に一本化し、タスクごとに独立した境界・例外ハンドラ・アリーナで実行する。
3. 互換性の維持:
   - 既存の `make-budgeted-task` や `budgeted-task?`、coroutine API との後方互換性を 100% 保持する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] スケジューラ・プリエンプション・チャネル・Supervisor で扱うタスク表現が `<task-context>` に統一されていること。
- [x] `make -C ulisp test_scheduler` および `make -C ulisp test_preemption` が 100% PASS すること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

