---
ID: 741
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] タスク正常終了時のクリーンアップ・DOWN通知および登録解除の実行 (ID: 741)

## 1. 概要 / Summary
正常に実行を終えたタスクに対して `task-handle-termination!` が実行されない。
このため `DOWN (normal)` シグナルが送信されず、監視元（Monitor/Link）、プロセス名レジストリ、タスク表のいずれからもタスクが解除されずメモリリークが発生する。さらに、`permanent` 再起動戦略を持つ子タスクが正常終了した際に再起動されない不具合が発生している。

### 再現手順 / Steps to Reproduce
1. 正常終了する処理 `(lambda () 42)` を実行するタスクを生成し、親プロセスから `monitor` または `link` する。
2. タスクが正常に値を返して終了する。
3. 親プロセスに `DOWN (normal)` メッセージが届かず、タスク表 (`task-table`) に当該 TID のレコードが永久に残存する。
4. Supervisor 下の `permanent` 子プロセスが再起動されない。

### 再現環境 / Environment
- OS / Env: All Platforms
- File: `ulisp/runtime/concurrency/boundary.scm`, `ulisp/runtime/concurrency/links.scm`, `ulisp/runtime/concurrency/scheduler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/boundary.scm`](../../ulisp/runtime/concurrency/boundary.scm)
- [ ] [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [`ulisp/tests/test_links_monitors.scm`](../../ulisp/tests/test_links_monitors.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
例外発生時（異常終了時）は例外境界の catch 節から `task-handle-termination!` が呼ばれているが、正常復帰（境界が `ok` を返したパス）では単に結果値を返してそのままスケジューラへ復帰している。そのため、タスク終了時ライフサイクル共通処理（`DOWN` 通知送出、リンクタスクへのシグナル波及、タスクレジストリ・タスク表からの登録解除）がバイパスされている。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: タスクの末尾で明示的に `(task-exit! 'normal)` を呼び出す。
* **恒久対策 (Permanent Fix)**: タスク境界の正常終了パスにおいて、境界が `ok` を返した際にも `(task-exit! 'normal)` を自動的に通すように統一する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/741-handle-normal-task-termination-and-cleanup`

1. `ulisp/runtime/concurrency/boundary.scm`:
   - タスク評価完了（正常リターン）時に、戻り値を保持した上で `(task-handle-termination! task 'normal)` を呼び出す。
2. `ulisp/runtime/concurrency/links.scm`:
   - `normal` 終了理由による `DOWN` メッセージのフォーマット生成および monitor/link 先への配信を保証する。
3. `ulisp/runtime/concurrency/supervisor.scm`:
   - `permanent` 指定された子が `DOWN (normal)` を受け取った場合にも再起動ポリシーに従って再起動を実行するように条件分岐を確認・修正。
4. `ulisp/tests/test_links_monitors.scm`:
   - 正常終了したタスクから `DOWN (normal)` が受信され、タスク表から登録抹消されることを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 正常終了したタスクから監視元へ `DOWN (normal)` が送信されること
- [ ] 正常終了後にタスク表およびレジストリから対象タスクが自動抹消されること
- [ ] `permanent` 戦略の子タスクが正常終了時にも再起動されること
- [ ] `ulisp/tests/test_links_monitors.scm` および `test_supervisor.scm` が PASS すること

