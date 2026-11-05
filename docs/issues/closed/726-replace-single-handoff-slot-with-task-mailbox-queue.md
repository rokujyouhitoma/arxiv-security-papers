---
ID: 726
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] タスク通知受け取り口のメールボックス (FIFO キュー) 化による DOWN/EXIT 通知と io_uring 完了結果の上書き消失防止 (ID: 726)

## 1. 概要 / Summary
現在、`<task-context>` の通知受け取り口が単一要素の `handoff-box` 1つしかなく、Monitor の `DOWN` 通知、Link の `EXIT` 通知、Channel の直接 handoff / poison 通知、および `io_uring` の完了通知（`io_uring.scm:449`）がすべて同じ欄を `task-set-handoff!`（および `channel.scm` 内の `atomic-set!`）で上書きし合っている。さらに `channel-recv!` で受信待ちに移行する際に `(atomic-set! (%task-handoff-box receiver-task) #f)` で既存の通知を消去してしまっている。そのため、複数のイベントが重なると通知や I/O の結果が消える不具合がある。通知の受け取り口を CAS ロックフリー FIFO メールボックス（キュー）に変更し、通知の上書き消失を防止する。

### 再現手順 / Steps to Reproduce
1. あるタスクが2つの子タスクを監視（または `io_uring` I/O を発行しつつ別タスクを監視）する。
2. 2つのイベント（例: `DOWN` 通知と `io_complete`、または2つの `DOWN` 通知）が連続して発生し、`task-set-handoff!` が2回呼ばれる。
3. 1つ目の通知が `handoff-box` 上で上書きされ消失する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/channel.scm`, `ulisp/runtime/concurrency/links.scm`, `ulisp/runtime/concurrency/io_uring.scm`, `ulisp/runtime/concurrency/supervisor.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [channel.sld](../../../ulisp/lib/ulisp/concurrency/channel.sld)
- [x] [supervisor.scm](../../../ulisp/runtime/concurrency/supervisor.scm)
- [x] [test_links_monitors.scm](../../../tests/concurrency/test_links_monitors.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `<task-context>` の `handoff-box` が元々単一のチャネルランデブー受け渡しスロット `(cons #t val)` として設計されていたにもかかわらず、`DOWN` / `EXIT` シグナル（`links.scm`）や `io_uring` 完了通知（`io_uring.scm:449`）、チャネル poison 通知（`channel.scm:1398, 1410`）も同じ単一ボックスに `atomic-set!` で書き込む実装になっていたため。
- また、`%channel-recv-core!`（`channel.scm:1177`）がサスペンド登録時に `(atomic-set! (%task-handoff-box receiver-task) #f)` を実行し、未処理の通知を破棄していたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `task-monitor` 呼び出し時に毎回個別の `notify-channel` を明示的に渡す。
* **恒久対策 (Permanent Fix)**: `<task-context>` の `handoff-box` を `atomic-cas!` によるロックフリー FIFO キュー（メールボックス）に拡張し、`task-set-handoff!` / `task-mailbox-enqueue!` を末尾追加、`task-take-handoff!` / `task-mailbox-dequeue!` を先頭取り出し、`task-handoff` / `task-mailbox-peek` を先頭参照として実装する。あわせて `channel.scm` 内の直接 `atomic-set!` を `task-set-handoff!` に統一し、サスペンド時の `#f` クリアを廃止する。また `supervisor-poll-down-signals!` でメールボックス内の複数の `DOWN` 通知を順次処理できるようにする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/726-task-notification-mailbox-queue`

1. `ulisp/runtime/concurrency/channel.scm` の `%task-handoff-box` を空時 `#f`・非空時 `(list (cons #t msg1) (cons #t msg2) ...)` を保持する CAS ロックフリー FIFO キューに変更する。
2. `task-set-handoff!` / `task-take-handoff!` / `task-handoff` / `task-has-handoff?` を FIFO キュー操作に更新し、明示的なメールボックス API（`task-mailbox-enqueue!`, `task-mailbox-dequeue!`, `task-mailbox-peek`, `task-mailbox-empty?`, `task-mailbox-size`）を追加する。
3. `channel.scm` 内のランデブー handoff（1046行目）および poison 通知（1398, 1410行目）を `task-set-handoff!` に統一し、1177行目の `#f` リセットを除去する。
4. `supervisor.scm` の `supervisor-poll-down-signals!` がメールボックス内の複数の `DOWN` 通知をすべて処理できるように更新する。
5. `tests/concurrency/test_links_monitors.scm` に複数の `DOWN` / `EXIT` / `io_complete` 通知が同一タスクに連続到着しても FIFO 順で1件も失われないことを検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 複数の `DOWN` / `EXIT` 通知および `io_uring` 完了通知が同時に到着しても、1件も失われず FIFO 順に取り出せること。
- [x] `make -C ulisp test_channel test_links_monitors test_io_uring test_supervisor lint_sexpr` がすべて PASS すること。

