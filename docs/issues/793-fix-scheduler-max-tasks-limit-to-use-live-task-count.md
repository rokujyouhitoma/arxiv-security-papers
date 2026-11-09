---
ID: 793
種別: Bug
優先度: Low
ステータス: Open (New)
---

# [BUG/SEC] スケジューラの最大タスク上限 (scheduler-max-tasks) 判定における累積値から生存タスク数への修正 (ID: 793)

## 1. 概要 / Summary
Synapse のスケジューラ（`scheduler.scm`）において、タスク生成時の上限判定が「現在生存しているタスク数」ではなく「累積タスク生成数（`scheduler-tasks-spawned`）」と比較されているため、長時間稼働時に累積上限（1,000 万回）に達すると Supervisor の再起動を含む全 spawn が恒久的に失敗する不具合を修正する。

`*scheduler-max-tasks*`（10,000,000）は本来、DoS やリソース枯渇（CWE-400）を防ぐために「同時に存在できる最大タスク数」を制限する目的であるが、現在の実装ではタスクが終了（exit / terminate）してもカウンターが減算されない。このため、正常にタスクの生成・完了を繰り返すシステムであっても、累積カウントが上限に到達した時点で即座に全タスク生成が停止する。

### 再現手順 / Steps to Reproduce
1. スケジューラを起動し、短時間のタスクを生成・終了するループを継続的に実行する。
2. 累積生成数が `*scheduler-max-tasks*`（テスト環境では小さな閾値、本番では 1,000 万）に達する。
3. 現在生存しているタスク数が 0〜1 個であっても、次の `scheduler-spawn!` が `scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)` エラーで拒絶される。
4. Supervisor による子タスクの再起動も失敗し、システム全体が機能停止する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- File: `ulisp/runtime/concurrency/scheduler.scm` (`scheduler-spawn!`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [test_scheduler_input.scm](../../ulisp/build/test_scheduler_input.scm)
- [ ] [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/runtime/concurrency/scheduler.scm` の `scheduler-spawn!`（行 441-445）にて以下のように記述されている：
  ```scheme
  (let ((sp-cnt (scheduler-tasks-spawned sched)))
    (if (>= sp-cnt *scheduler-max-tasks*)
        (error "scheduler-spawn!: maximum spawned tasks limit exceeded (CWE-400)" sp-cnt)
        (let ((normalized (%normalize-task-context task)))
          (%scheduler-tasks-spawned-inc! sched)
  ```
- `scheduler-tasks-spawned` は単調増加する累積統計値であり、タスクが `task-exit!` やクリーンアップで回収された際にデクリメントされる生存タスクカウンター（`live-tasks-count`）が存在しない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `*scheduler-max-tasks*` の閾値を巨大な値に引き上げるか、定期的にスケジューラインスタンスを再生成する。
* **恒久対策 (Permanent Fix)**:
  - スケジューラ構造体に「現在生存タスク数（`scheduler-live-tasks`）」のアトミックカウンターを追加。
  - `scheduler-spawn!` 成功時にインクリメントし、`task-exit!` / `synapse-cleanup-task-resources!` による終了処理時にデクリメントする。
  - `*scheduler-max-tasks*` の比較対象を `scheduler-live-tasks` に変更する（累積統計値 `scheduler-tasks-spawned` はメトリクス用途として残す）。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/793-scheduler-live-tasks-limit`

1. `<work-stealing-scheduler>` に `live-tasks-box` を追加し、アトミックな増減 API を整備。
2. `scheduler-spawn!` での上限判定を `live-tasks-box` に基づくように変更。
3. タスク終了パス（`task-exit!`、panic クリーンアップ）で確実にデクリメントされるよう接続。
4. 意図的に上限値（例: 5 個）を設定したスケジューラにおいて、5 個同時に起動中は 6 個目が拒絶されるが、タスクが終了した後は直ちに次のタスクが spawn できることを確認するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] タスクが終了した後に生存タスクカウンターが正しく減算されること。
- [ ] 長時間のタスク生成・終了サイクルにおいて、累積生成数が上限を超えても生存タスク数が上限未満であれば正常に spawn できること。
- [ ] 意図的な同時タスク数超過時に適切に CWE-400 エラーが発生すること。

