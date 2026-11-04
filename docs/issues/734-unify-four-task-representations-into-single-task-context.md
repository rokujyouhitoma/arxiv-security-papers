---
ID: 734
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 4種類のタスク表現の <task-context> への一元化 (ID: 734)

## 1. 概要 / Summary
現在、Synapse ランタイム内には `<task-context>`（`channel.scm`）、`<budgeted-task>`（`preempt.scm`）、`<coroutine-context>`（`context.scm`）、および生の `procedure`（thunk）という4種類のタスク表現が並存しており、`scheduler-execute-task!` 等で毎回分岐処理している（項目 A7）。これら4種類のタスク表現を `<task-context>` 1つに統一し、すべてのタスクが一貫してリダクション管理・例外境界・リンク／監視・アリーナを持てるようにする。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 6.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [preempt.scm](../../ulisp/runtime/concurrency/preempt.scm)
- [ ] [context.scm](../../ulisp/runtime/concurrency/context.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/734-unify-task-context-representation`

1. `<task-context>` に実行本体（thunk / coroutine）や初期 reduction budget、exhaustions カウンタを統合する。
2. `make-budgeted-task` や `scheduler-spawn!` に渡された thunk / coroutine もすべて `<task-context>` として生成・管理するように統一し、既存 API は `<task-context>` 上の互換アクセサとして維持する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] スケジューラ・プリエンプション・チャネル・Supervisor で扱うタスク表現が `<task-context>` に統一されていること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

