---
ID: 725
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] タスク監視 (Monitor/Link) 登録と終了処理の CAS アトミック化・受付締め切り機構の実装 (ID: 725)

## 1. 概要 / Summary
現在、`task-monitor`（および `task-link!`）は「対象タスクの状態が `'terminated` か確認する処理」と「監視リストへ CAS で登録する処理」が別々のステップに分かれている（項目 B4）。そのため、状態確認直後に対象タスクが終了して `monitored-by-box` を空にすると、登録された監視者に `DOWN` 通知が永遠に届かない競合（TOCTOU Race, CWE-362）が存在する。「状態を確認してから登録する」処理を1回の CAS にまとめ、終了処理側は登録の受付を締め切ってから通知を出すように修正する。

### 再現手順 / Steps to Reproduce
1. タスク A がタスク B に対して `(task-monitor task-a task-b ch)` を呼び出し、`(eq? (task-state target-task) 'terminated)` が `#f` と判定される。
2. 直後に別 Worker 上でタスク B が終了し、`(atomic-swap! (task-monitored-by-box task-b) '())` を実行する。
3. タスク A が `task-monitored-by-box` にエントリを CAS 追加するが、タスク B の通知ループは既に終わっているため `DOWN` 通知が失われる。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/links.scm`, `ulisp/runtime/concurrency/channel.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [links.scm](../../../ulisp/runtime/concurrency/links.scm)
- [x] [channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [test_links_monitors.scm](../../../tests/concurrency/test_links_monitors.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- タスクの生死状態（`%task-state`）と被監視リスト（`monitored-by-box` / `links-box`）が別個の変数として非アトミックに参照・更新されており、終了時の「受付締め切り（閉鎖マーク `'closed`）」状態が存在しないため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: タスク起動前（スケジューラ投入前）にのみ `task-monitor` を呼ぶ。
* **恒久対策 (Permanent Fix)**: 被監視・リンクリストのボックスに閉鎖状態 `'closed` を導入し、登録側は「未閉鎖の確認（`'closed` でなくかつ `'terminated` でない）とリスト追加」を1回の `atomic-cas!` で行い、終了処理側は `(atomic-swap! box 'closed)` で受付を `'closed` に締め切ってから通知を送出する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/725-atomic-monitor-registration-and-death`

1. `channel.scm` の `task-state-set!` で `'terminated` が設定された場合にも `monitored-by-box` と `links-box` がリストのままなら `'closed` へ遷移させ、`task-links` / `task-monitored-by` アクセサが `'closed` の場合は `'()` を返すようにする。
2. `links.scm` の `task-handle-termination!` で `monitored-by-box` および `links-box` を `'closed`（受付締切）へ `atomic-swap!` してから既存の登録者へ通知を出す（既に `'closed` なら二重通知しない）。
3. `task-monitor` および `task-link!` で、対象ボックスの CAS ループ内で `cur` が `'closed`（または `task-state` が `'terminated`）なら CAS 登録を行わず即座に `'noproc` の `DOWN` / `EXIT` 通知を出し、未閉鎖リストであれば1回の `atomic-cas!` で登録を完了させる。
4. `test_links_monitors.scm`（Group 7）に、受付締切状態（`'closed`）やタスク終了との競合下で `task-monitor` / `task-link!` を呼んだ際に通知漏れが0件であることを検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 監視登録とタスク死亡が同時に発生しても、必ず「登録が成功して終了処理から `DOWN` が出る」か「締切を検知して即座に `'noproc` の `DOWN` が出る」かのどちらかになり、通知漏れが 0 件であること。
- [x] `make -C ulisp test_links_monitors test_let_it_crash lint_sexpr` がすべて PASS すること。

