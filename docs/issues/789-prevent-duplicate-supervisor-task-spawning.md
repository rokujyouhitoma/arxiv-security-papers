---
ID: 789
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] 複数子タスク同時終了時における同一 Supervisor タスクの重複投入 (scheduler-spawn!) 抑止 (ID: 789)

## 1. 概要 / Summary
Synapse の Supervisor 配下で複数の子タスクが同時に異常終了した場合に、monitor DOWN 通知ごとに同一の Supervisor タスクが重複して `scheduler-spawn!` され、複数の worker スレッドで同時に実行されてしまう競合不具合を修正する。

受信処理そのものは `processing-box` によるアトミック保護があるものの、タスク境界が管理する `escape-k`、タスク実行中フラグ、レジスタ退避領域、スケジューラ側の実行中タスク管理テーブルが同一タスク上で競合し、状態不整合やデータ破壊を引き起こす。

### 再現手順 / Steps to Reproduce
1. Supervisor 配下に複数の子タスクを起動する。
2. 複数の子タスクをマルチスレッド環境下（または同一タイムスライス内）で同時に強制終了または panic させる。
3. monitor DOWN シグナルのディスパッチフック（`set-monitor-down-dispatch-hook!`）が各子の終了ごとに同一 Supervisor タスクを `scheduler-spawn!` する。
4. 複数の worker スレッドが同一の Supervisor タスクを同時にポップして実行を開始し、境界状態やタスクコンテキストが破損する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- File: `ulisp/runtime/concurrency/supervisor.scm` (`set-monitor-down-dispatch-hook!`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [test_supervisor_input.scm](../../ulisp/build/test_supervisor_input.scm)
- [ ] [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/runtime/concurrency/supervisor.scm` の `set-monitor-down-dispatch-hook!`（行 696-714）において、DOWN シグナルを受け取るたびに無条件で以下を実行している：
  ```scheme
  (task-state-set! obs-task 'ready)
  (%supervisor-enqueue-child! sup obs-task)
  ```
- ここで `obs-task` は Supervisor タスク自身であり、既にスケジューラのランキューに積まれているか実行中であるかを検査せずに再投入しているため、アトミックな投入ガードが存在しない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: シングルスレッドスケジューラでのみ実行し、ワーカースレッド間での同時実行を回避する。
* **恒久対策 (Permanent Fix)**:
  - Supervisor コンテキスト内に「投入済み・実行中フラグ（`enqueued-box` または `scheduled?`）」を用意する。
  - monitor DOWN 受信時は CAS（Compare-And-Swap）で未投入状態（`#f` -> `#t`）に遷移できた場合のみ `scheduler-spawn!` を実行する。
  - Supervisor タスクがキューの全メッセージを処理し終えて待機状態に戻る際に、CAS でフラグをクリアする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/789-supervisor-task-coalesced-spawn`

1. `<supervisor-context>` にアトミックな `enqueued-box` を追加。
2. `set-monitor-down-dispatch-hook!` 内で、`atomic-cas!` により二重投入を抑止するガードロジックを実装。
3. Supervisor タスクの処理ループ完了時、未処理メッセージが残っていなければ `enqueued-box` を `#f` に戻し、残っていれば自身を再スケジュールする Coalescing 機構を確立。
4. マルチワーカースレッド環境下で 10 個以上の子タスクを一斉に crash させ、Supervisor タスクが重複実行されずに整合性を保って全子タスクを再起動できる結合テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 複数の子が同時に終了しても同一 Supervisor タスクが同時に 2 つ以上の worker で実行されないこと。
- [ ] すべての DOWN シグナルが取りこぼしなく処理され、全滅した子が規定のポリシー通り再起動されること。
- [ ] マルチスレッドストレステストにおいて競合エラー（CWE-362）が 0 件であること。

