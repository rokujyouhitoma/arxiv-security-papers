---
ID: 727
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Supervisor のタスク駆動化と子タスク DOWN 通知からの supervisor-handle-child-down! 自動ディスパッチ接続 (ID: 727)

## 1. 概要 / Summary
現在、`supervisor.scm` には再起動戦略を処理する `supervisor-handle-child-down!` が実装されているものの、Supervisor 自身がタスクとして動いておらず、子タスクが死んだ際の `DOWN` 通知を自動的に受け取って `supervisor-handle-child-down!` を呼ぶ配線が未接続である（項目 C7）。Supervisor をタスクとして動かし、子を monitor させ、`DOWN` を受け取ったら自動的に `supervisor-handle-child-down!` を呼ぶように接続する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/727-connect-supervisor-child-down-dispatch`

1. Supervisor をタスクとして実行可能にし、子タスク生成時に Supervisor のメールボックス／通知チャネルへ `task-monitor` を接続する。
2. 子タスクの異常終了・終了に伴って送出される `('DOWN ref 'process tid reason)` を Supervisor タスクが受信した際、自動的に `supervisor-handle-child-down!` を呼び出して再起動戦略を実行する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] テストコード側から手動で `supervisor-handle-child-down!` を呼ばなくても、子タスクの死亡通知によって Supervisor が自律的に子を再起動すること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

