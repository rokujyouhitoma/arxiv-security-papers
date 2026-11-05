---
ID: 727
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] Supervisor のタスク駆動化と子タスク DOWN 通知からの supervisor-handle-child-down! 自動ディスパッチ接続 (ID: 727)

## 1. 概要 / Summary
現在、`supervisor.scm` には再起動戦略を処理する `supervisor-handle-child-down!` が実装されているものの、Supervisor 自身がタスクとして動いておらず、子タスクが死んだ際の `DOWN` 通知を自動的に受け取って `supervisor-handle-child-down!` を呼ぶ配線が未接続である（項目 C7）。Supervisor をタスクとして動かし、子を monitor させ、`DOWN` を受け取ったら自動的に `supervisor-handle-child-down!` を呼ぶように接続する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 8.4.3)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [supervisor.scm](../../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [links.scm](../../../ulisp/runtime/concurrency/links.scm)
- [x] [test_supervisor.scm](../../../tests/concurrency/test_supervisor.scm)

---

## 4. 根本原因分析 (RCA) / Root Cause Analysis
- `make-supervisor` で生成される `sup-task` の `next-run` クロージャが `#f` のままであり、また `links.scm` の `%deliver-monitor-down!` が `observer-task` のメールボックスに `DOWN` メッセージを格納して `task-wake!` するのみで、Supervisor タスクのディスパッチャ（`supervisor-poll-down-signals!` / `supervisor-handle-child-down!`）を起動する配線が存在しなかったため。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/727-connect-supervisor-child-down-dispatch`

1. `ulisp/runtime/concurrency/links.scm` に `*monitor-down-dispatch-hook-box*` と `set-monitor-down-dispatch-hook!` を追加し、`%deliver-monitor-down!` で監視タスクへ `DOWN` 通知を配送・起床した際にディスパッチフックを呼び出す。
2. `ulisp/runtime/concurrency/supervisor.scm` の `make-supervisor` で `sup-task` の `task-next-run` に `(lambda () (supervisor-poll-down-signals! sup))` を設定し、Supervisor 自身をタスクとしてスケジューラ実行可能にする。
3. `supervisor-start!` / `supervisor-stop!` で稼働中 Supervisor タスクを `*active-supervisors-by-task-box*` に登録・解除し、`set-monitor-down-dispatch-hook!` を通じて子タスクの `DOWN` 通知到着時に自動的に `supervisor-poll-down-signals!` → `supervisor-handle-child-down!` をディスパッチする。
4. `tests/concurrency/test_supervisor.scm` に、子タスクが異常終了した際に手動で `supervisor-handle-child-down!` や `supervisor-poll-down-signals!` を呼ばなくても自動的に子タスクが再起動されることを検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] テストコード側から手動で `supervisor-handle-child-down!` を呼ばなくても、子タスクの死亡通知によって Supervisor が自律的に子を再起動すること。
- [x] `make -C ulisp test_supervisor test_let_it_crash lint_sexpr` がすべて PASS すること。

