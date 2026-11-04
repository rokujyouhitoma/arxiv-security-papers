---
ID: 725
種別: Bug
優先度: High
ステータス: Open (New)
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
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- タスクの生死状態（`%task-state`）と被監視リスト（`monitored-by-box` / `links-box`）が別個の変数として非アトミックに参照・更新されており、終了時の「受付締め切り（閉鎖マーク）」状態が存在しないため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: タスク起動前（スケジューラ投入前）にのみ `task-monitor` を呼ぶ。
* **恒久対策 (Permanent Fix)**: 被監視・リンクリストのボックスに閉鎖状態（例: `'closed` または状態付きペア）を持たせ、登録側は「未閉鎖の確認と追加」を1回の CAS で行い、終了処理側は `atomic-swap!` で受付を `'closed` に締め切ってから通知を送出する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/725-atomic-monitor-registration-and-death`

1. `task-handle-termination!` で `monitored-by-box` および `links-box` を `'closed`（受付締切）へ `atomic-swap!` してから既存の登録者へ通知を出す。
2. `task-monitor` および `task-link!` で、対象ボックスが `'closed` なら即座に `'noproc` 通知を出し、リストであれば1回の `atomic-cas!` で登録を完了させる。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 監視登録とタスク死亡が同時に発生しても、必ず「登録が成功して終了処理から `DOWN` が出る」か「締切を検知して即座に `'noproc` の `DOWN` が出る」かのどちらかになり、通知漏れが 0 件であること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

