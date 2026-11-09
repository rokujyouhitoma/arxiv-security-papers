---
ID: 789
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] 複数子タスク同時終了時における同一 Supervisor タスクの重複投入 (scheduler-spawn!) 抑止 (ID: 789)

## 1. 概要 / Summary
Synapse の Supervisor 配下で複数の子タスクが同時に異常終了した場合に、monitor DOWN 通知ごとに同一の Supervisor タスクが重複して `scheduler-spawn!` され、複数の worker スレッドで同時に実行されてしまう競合不具合（CWE-362 / CWE-662）を修正する。

Supervisor のタスクは受信メールボックス内のメッセージを順次処理するアクター構造を持つが、DOWN 通知フック（`set-monitor-down-dispatch-hook!`）が無条件に `scheduler-spawn!` を実行するため、子が同時にクラッシュした際に同一の `sup-task` がスケジューラのランキューに複数投入される。
受信処理自体は `processing-box` によるアトミックロックがあるものの、スケジューラ側の `scheduler-execute-task!` およびタスク境界（`with-synapse-task-boundary`）が管理する以下のタスクコンテキスト状態が同一タスク上で並行して書き換えられ、深刻な状態不整合やメモリ破壊（Use-After-Free / 誤ったエスケープジャンプ）を引き起こす：
1. `task-escape-k-box` (境界脱出継続)
2. `task-executing-box` (タスク実行中フラグ)
3. `task-handler-chain-box` (例外ハンドラ連鎖)
4. スケジューラの Worker TLS 実行中タスク参照 (`*worker-current-task-tls*`)

### 再現手順 / Steps to Reproduce
1. マルチワーカー対応スケジューラ（`make-work-stealing-scheduler`、Worker 数 >= 2）を起動する。
2. Supervisor 配下に複数の子タスク（例: 4〜10 個）を起動する。
3. 複数の子タスクをマルチスレッド環境下（または同一タイムスライス内）で同時に強制終了または panic させる。
4. monitor DOWN シグナルのディスパッチフック（`set-monitor-down-dispatch-hook!`）が各子の終了ごとに同一 Supervisor タスクを `scheduler-spawn!` する。
5. 複数の worker スレッドが同一の Supervisor タスクを同時にデキューして `with-synapse-task-boundary` を並行実行し、タスク境界コンテキストが破損する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- 対象ファイル:
  - `ulisp/runtime/concurrency/supervisor.scm` (`<supervisor-context>`, `%supervisor-schedule-actor!`, `%supervisor-drain-loop!`, `set-monitor-down-dispatch-hook!`)
  - `ulisp/lib/ulisp/concurrency/supervisor.sld` (シンボル export)
  - `tests/concurrency/test_supervisor.scm` (並列子クラッシュおよびアトミック状態遷移テスト)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm) — `<supervisor-context>` への `enqueued-box` 追加、4状態アクター遷移機構（`idle`, `scheduled`, `running`, `running_notified`）および Coalesced スケジューリングの実装
- [ ] [supervisor.sld](../../ulisp/lib/ulisp/concurrency/supervisor.sld) — `supervisor-enqueued-state` の export
- [ ] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm) — Group 16: Coalesced Supervisor Spawning & Multi-Child Simultaneous Crash Isolation テストの追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
### メカニズム詳細
1. **無条件なランキュー投入**:
   - `ulisp/runtime/concurrency/supervisor.scm` の `set-monitor-down-dispatch-hook!`（行 696-714）:
     ```scheme
     (if (and sched (procedure? scheduler-spawn!) (scheduler-running? sched))
         ;; Actor mode: wake up supervisor task and enqueue to scheduler
         (begin
           (task-state-set! obs-task 'ready)
           (%supervisor-enqueue-child! sup obs-task))
         ...)
     ```
   - ここで `obs-task` は Supervisor タスク自身（`sup-task`）である。
   - 子タスク A がクラッシュした際に Worker 1 が hook を呼び出し、`scheduler-spawn!` を実行。
   - 同時に子タスク B がクラッシュした際に Worker 2 が hook を呼び出し、同一の `obs-task` に対して再び `scheduler-spawn!` を実行。
2. **ランキューへの同一タスク二重投入**:
   - スケジューラのローカルデックまたはグローバル Michael-Scott キューに、同一の `<task-context>` ポインタが 2 つ以上積まれる。
3. **並行実行によるタスク境界の破壊**:
   - Worker 1 と Worker 2 がそれぞれ同じ `sup-task` をポップして `scheduler-execute-task!` を呼ぶ。
   - `scheduler-execute-task!` は以下を行う：
     ```scheme
     (let ((res (with-synapse-task-boundary ctx nxt))) ...)
     ```
   - `with-synapse-task-boundary` は `ctx` の `escape-k-box` をカレントスタックフレームの継続で上書きし、`task-executing-box` を `#t` にセットする。
   - Worker 1 が処理中に Worker 2 が `escape-k-box` を書き換えると、Worker 1 内で例外が発生した際に Worker 2 のスタックフレームへジャンプしてスタック破壊を引き起こす。
   - また、Worker 2 が `supervisor-poll-down-signals!` の `processing-box` CAS に失敗して早期リターンした際、Worker 2 のエピローグが `task-executing-set! #f` を実行し、Worker 1 がまだ実行中であるにもかかわらず実行中フラグが解除される。

### 単純な Boolean フラグによる Lost Wakeup の危険性
単に `enqueued?` という 1 つの真偽値フラグを設けて `(atomic-cas! enqueued? #f #t)` するだけでは、**Lost Wakeup（起床通知の消失）** が発生する：
1. `sup-task` が Worker 1 で実行を開始し、`enqueued?` を `#f` に戻す。
2. Worker 1 がメールボックスを空と判定し、ループを抜ける直前の隙間に子タスク C がクラッシュして DOWN シグナルを送信。
3. もし `enqueued?` が `#t` のままだと新規 spawn が抑止され、かつ Worker 1 は既にメールボックス確認を終えて終了するため、子タスク C の DOWN が永久に処理されずスタックする。
4. したがって、Tokio / Erlang / Akka で標準的に用いられる **4 状態アクター遷移モデル（Coalescing State Machine）** が不可欠である。

---

## 4. セキュリティ・整合性設計 (Security & Integrity Architecture)

### 脅威分析
- **CWE-362 (Race Condition / Concurrent Execution of Non-Reentrant Task)**: 単一スレッドでの実行を前提とする `<task-context>` が複数ワーカーで同時実行され、データ競合が発生する。
- **CWE-662 (Improper Synchronization)**: 実行中フラグおよび脱出継続の競合により、不正なスレッドスタックへの長距離ジャンプが発生する。
- **CWE-843 (Type / State Confusion)**: スケジューラランキューに重複存在することによるライフサイクル状態の不整合。

### 4 状態アクター遷移モデル (Formal State Machine)
`<supervisor-context>` にアトミックな `enqueued-box` を新設し、以下の 4 状態を厳密に管理する：

```
                +---------------------------------------+
                |                                       |
                v                                       |
           +---------+     signal arrive (CAS)     +-----------+
           |  idle   | --------------------------> | scheduled |
           +---------+                             +-----------+
                ^                                       |
                | CAS (empty && cur==running)           | worker pops & runs
                |                                       v
         +---------------+     signal arrive       +-----------+
         |  running_     | <---------------------- |  running  |
         |  notified     |                         +-----------+
         +---------------+
                |
                | drain done -> resets to 'running'
                | and loops back to poll mailbox!
                v
```

1. **`idle` (休眠)**: Supervisor タスクはランキューに存在せず、実行もされていない待機状態。
2. **`scheduled` (投入済み)**: ランキューに投入され、Worker によるデキュー待ちの状態。この状態での追加シグナル到着は無視（Coalesce: 既にランキューにあるため二重投入しない）。
3. **`running` (実行中)**: いずれかの Worker が `sup-task` をポップし、メールボックス処理ループを実行中。
4. **`running_notified` (実行中＋新規到着)**: Worker が実行中に新たなシグナルが到着した状態。Worker はメールボックスを1回空にした後、直ちに終了せず自律的にもう一度ポーリングを継続する。

### 防御策 (Mitigations)
- **多重投入の完全排除 (Zero Duplicate Spawns)**:
  `scheduler-spawn!` が呼ばれるのは `idle -> scheduled` の CAS に成功した唯一の瞬間のみ。複数スレッドから同時にシグナルが押し寄せても、勝者は厳密に 1 スレッドに限定される。
- **起床通知消失の完全防止 (Zero Lost Wakeups)**:
  Worker がループを終了して `idle` に戻る際は、メールボックスが空であることの確認と `running -> idle` の CAS が不可分に行われる。CAS 失敗時または `running_notified` 検知時はループを継続して残余メッセージを確実に全件ドレインする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/789-supervisor-task-coalesced-spawn`

### Step 1: `<supervisor-context>` に `enqueued-box` を追加
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - `<supervisor-context>` レコード定義に `enqueued-box` フィールドを追加。
  - `%supervisor-enqueued-box` アクセサを定義。
  - 公開 API `(supervisor-enqueued-state sup)` を提供（デバッグ・テスト用）。
  - `make-supervisor` 内で `(make-atomic-box 'idle)` を初期化。

### Step 2: `%supervisor-schedule-actor!` の実装
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - シグナル到着時に安全に Supervisor タスクをスケジュールするヘルパーを実装：
    ```scheme
    (define (%supervisor-schedule-actor! sup sup-task)
      (let ((box (%supervisor-enqueued-box sup)))
        (let retry ()
          (let ((cur (atomic-ref box)))
            (cond
              ;; Case 1: Idle -> transition to 'scheduled and enqueue once
              ((eq? cur 'idle)
               (if (atomic-cas! box 'idle 'scheduled)
                   (begin
                     (task-state-set! sup-task 'ready)
                     (%supervisor-enqueue-child! sup sup-task)
                     #t)
                   (retry)))
              ;; Case 2: Already scheduled in runqueue -> coalesced, nothing to do
              ((eq? cur 'scheduled)
               #t)
              ;; Case 3: Currently running on a worker -> mark 'running_notified so worker loops
              ((eq? cur 'running)
               (if (atomic-cas! box 'running 'running_notified)
                   #t
                   (retry)))
              ;; Case 4: Already running and marked notified -> nothing to do
              ((eq? cur 'running_notified)
               #t)
              (else #f))))))
    ```

### Step 3: `%supervisor-drain-loop!` の実装と `sup-task` ループの改修
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - `sup-task` の `task-next-run` に登録するドレインループを実装：
    ```scheme
    (define (%supervisor-drain-loop! sup)
      (let ((box (%supervisor-enqueued-box sup)))
        ;; Transition from 'scheduled to 'running
        (atomic-cas! box 'scheduled 'running)
        (let loop ((last-res #f))
          (let ((res (supervisor-poll-down-signals! sup)))
            (let check-next ()
              (let ((cur (atomic-ref box)))
                (cond
                  ;; If new signals arrived while we were polling:
                  ((eq? cur 'running_notified)
                   (atomic-set! box 'running)
                   (loop res))
                  ;; If no new signals were notified, try to return to 'idle:
                  ((eq? cur 'running)
                   (if (task-has-handoff? (supervisor-task sup))
                       (loop res)
                       (if (atomic-cas! box 'running 'idle)
                           res
                           (check-next))))
                  (else res))))))))
    ```
  - `make-supervisor` において `task-next-run-set!` に `(lambda () (%supervisor-drain-loop! sup))` を設定。

### Step 4: `set-monitor-down-dispatch-hook!` のディスパッチ更新
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - `set-monitor-down-dispatch-hook!` 内の直接 enqueue を `%supervisor-schedule-actor!` の呼び出しに切り替え。

### Step 5: `supervisor-stop!` でのクリーンアップ
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - `supervisor-stop!` において `(atomic-set! (%supervisor-enqueued-box sup) 'idle)` を実行。

### Step 6: `supervisor.sld` の export 追加
- [supervisor.sld](../../ulisp/lib/ulisp/concurrency/supervisor.sld):
  - `supervisor-enqueued-state` を export に追加。

### Step 7: 結合テスト (Group 16) の追加
- [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm):
  - `Group 16: Coalesced Supervisor Spawning & Multi-Child Simultaneous Crash Isolation (Issue #789)` を新設。
  - 16.1: 状態遷移ユニットテスト (`idle` -> `scheduled` -> `running` -> `running_notified` -> `idle`)。
  - 16.2: 同一シグナルのバースト到着時に `scheduler-spawn!` が重複呼び出しされないことの検証。
  - 16.3: マルチワーカー環境（Worker 数 4）で 10 個の子タスクを同時に強制終了させた際、Supervisor タスクが一度も重複実行されず、全 10 個の子タスクが正確に 1 度ずつ再起動されることの検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 複数の子が同時に終了しても同一 Supervisor タスクが同時に 2 つ以上の worker で実行されないこと。
- [ ] すべての DOWN シグナルが取りこぼしなくドレインされ、全滅した子が規定のポリシー通り 100% 確実に再起動されること。
- [ ] `supervisor-enqueued-state` が `idle`, `scheduled`, `running`, `running_notified` を正確に遷移すること。
- [ ] マルチスレッドストレステストにおいてタスクコンテキスト破壊（CWE-362 / CWE-662）が 0 件であること。
- [ ] `make test_supervisor` および全並行性回帰テスト（`test_scheduler`, `test_multithread_scheduler` 等）が 100% PASS すること。
- [ ] 相対パス規則および Python 構文・リンターエラー 0 件が保証されていること。
