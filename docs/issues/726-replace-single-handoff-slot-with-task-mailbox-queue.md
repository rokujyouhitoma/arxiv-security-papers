---
ID: 726
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] タスク通知受け取り口のメールボックス (FIFO キュー) 化による DOWN/EXIT 通知と io_uring 完了結果の上書き消失防止 (ID: 726)

## 1. 概要 / Summary
現在、`<task-context>` の通知受け取り口が単一要素の `handoff-box` 1つしかなく、Monitor の `DOWN` 通知、Link の `EXIT` 通知、Channel の直接 handoff / poison 通知、および `io_uring` の完了通知（`io_uring.scm:449`）がすべて同じ欄を `task-set-handoff!` で上書きし合っている。そのため、複数のイベントが重なると通知や I/O の結果が消える不具合がある。通知の受け取り口をメールボックス（FIFO キュー）に変更し、通知の上書き消失を防止する。

### 再現手順 / Steps to Reproduce
1. あるタスクが2つの子タスクを監視（または `io_uring` I/O を発行しつつ別タスクを監視）する。
2. 2つのイベント（例: `DOWN` 通知と `io_complete`、または2つの `DOWN` 通知）が連続して発生し、`task-set-handoff!` が2回呼ばれる。
3. 1つ目の通知が `handoff-box` 上で上書きされ消失する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/channel.scm`, `ulisp/runtime/concurrency/links.scm`, `ulisp/runtime/concurrency/io_uring.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [io_uring.scm](../../ulisp/runtime/concurrency/io_uring.scm)
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `<task-context>` の `handoff-box` が元々単一のチャネルランデブー受け渡しスロットとして設計されていたにもかかわらず、後から追加された `DOWN` / `EXIT` シグナルや `io_uring` 完了通知も同じ単一ボックスに `atomic-set!` で書き込む実装になっていたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `task-monitor` 呼び出し時に毎回個別の `notify-channel` を明示的に渡す。
* **恒久対策 (Permanent Fix)**: タスクの通知受け取り口をロックフリー FIFO キュー（メールボックス）にし、`DOWN` / `EXIT` 通知・チャネル handoff・`io_uring` 完了結果が上書きされずに順序通り取り出せるようにする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/726-task-notification-mailbox-queue`

1. `<task-context>` の通知受け取り口をロックフリーキュー（メールボックス）に拡張する。
2. `task-set-handoff!` / `task-take-handoff!`（およびメールボックス送受信 API）をキューへの enqueue / dequeue として実装し、複数イベント到着時の上書き消失を解消する。
3. `links.scm`（`DOWN` / `EXIT`）、`channel.scm`、`io_uring.scm` の通知経路をメールボックスに統一または分離する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 複数の `DOWN` / `EXIT` 通知および `io_uring` 完了通知が同時に到着しても、1件も失われず FIFO 順に取り出せること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

