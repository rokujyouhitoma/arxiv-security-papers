---
ID: 798
種別: Bug
優先度: Medium
ステータス: Closed
完了日: 2026-11-10
---

# [BUG/CONCURRENCY] Supervisor の idle 状態復帰とスケジューラ後処理間のレースコンディション解消 (ID: 798)

## 1. 概要 / Summary
Issue #788 および #789 により、Supervisor タスクの重複投入抑止機構（`idle`, `scheduled`, `running`, `running_notified` の 4 状態マシン）が導入された。
しかし、状態遷移とスケジューラ内部のタスク境界処理の順序関係に起因する深刻な競合窓（Race Condition Window）が残存している。

現行の実装では、Supervisor の実行 thunk 内で呼ばれる `%supervisor-drain-loop!` の末尾において、未処理シグナルがなくなったと判定した時点で直接 `(atomic-cas! box 'running 'idle)` を発行している。
しかし、この時点ではまだタスク境界（`with-synapse-task-boundary`）を脱出しておらず、スケジューラの後処理（レジスタ・エスケープ継続復元、`task-executing-set! #f`、および `task-state-set! ctx 'waiting'`）が完了していない。

もしこのわずかな隙間（TOCTOU 窓）に別ワーカー上で子タスクが異常終了して次の `DOWN` シグナルが到着した場合：
1. `box` が既に `'idle` であるため、`%supervisor-schedule-actor!` は即座に `atomic-cas! box 'idle 'scheduled` に成功し、`sup-task` を runqueue に投入する。
2. 別の worker スレッドが即座に `sup-task` を pop し、`scheduler-execute-task!` で `task-state-set! ctx 'running'` やコンテキスト復帰を開始する。
3. 一方、元のワーカーではまだ脱出処理の最中であり、元のワーカーの `task-state-set! ctx 'waiting'` やスタック/継続復元処理が、新ワーカーの実行中コンテキストを上書き・破壊してしまう（CWE-362 / CWE-662）。

本 Issue では、Supervisor の `idle` 復帰 CAS をタスク内コードから完全に切り離し、スケジューラがコンテキストを完全に静止化（`waiting` への変更および境界脱出）した直後の境界脱出後コールバック（post-task-boundary hook）において安全に実行するようリファクタリングし、多重実行およびコンテキスト破壊を根本から防止する。

### 再現手順 / Steps to Reproduce
1. マルチワーカー環境（ワーカー数 4）上で Supervisor タスクを常駐稼働させる。
2. 多数の子タスク群を非同期かつ高頻度に連続クラッシュさせ、Supervisor がメールボックス受信ループを抜ける瞬間と、次の `DOWN` シグナル受信タイミングを意図的に衝突させる。
3. 2 つのワーカー上で同一 Supervisor の実行フラグ（`task-executing`）やタスク状態（`running` vs `waiting`）が競合し、アサーションエラーや二重実行が発生する現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- Target Files:
  - `ulisp/runtime/concurrency/channel.scm`
  - `ulisp/runtime/concurrency/scheduler.scm`
  - `ulisp/runtime/concurrency/supervisor.scm`
  - `tests/concurrency/test_supervisor.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm)
  - `task-resident-set!`: 真偽値 `#t` / `#f` に加え、境界脱出時コールバック（`procedure?`）の受け入れをサポート。
  - `task-resident?`: 真偽値およびプロシージャのいずれがセットされている場合でも `#t` を返却（後方互換性 100% 維持）。
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
  - `scheduler-execute-task!`: `task-resident?` タスクが `with-synapse-task-boundary` を脱出し、`(task-state-set! ctx 'waiting)` を完了した直後に、登録された post-boundary hook を安全に呼び出す。
- [x] [ulisp/runtime/concurrency/supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
  - `make-supervisor`: `sup-task` の `task-resident-set!` に post-boundary hook（`%supervisor-post-drain-hook!`）を登録。
  - `%supervisor-drain-loop!`: スケジューラ経由実行時に `idle` への即時復帰を遅延（フックへ委譲）。
  - `%supervisor-post-drain-hook!`: スケジューラがコンテキストを静止化させた後に呼び出され、`running` $\to$ `idle` への CAS、または脱出中に到着した `running_notified` の安全な再スケジュール（`scheduled` $\to$ `ready` $\to$ re-enqueue）を実施。
- [x] [tests/concurrency/test_supervisor.scm](../../tests/concurrency/test_supervisor.scm)
  - Group 17 として、4 ワーカー環境における高頻度バーストクラッシュ下での Supervisor 単一実行性・コンテキスト不変性ストレステストを追加。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- Supervisor が自身の受信処理を終えて状態を `idle` に戻す CAS を発行する契機が、スケジューラが当該タスクのレジスタ/スタック/フラグの後処理（`task-state-set! ctx 'waiting'` 等）を完了するより前（タスク実行 thunk の内部）で行われていた。
- このため、CAS 成功からスケジューラの脱出処理完了までのわずかな時間に新しいシグナルが到着すると、別のスレッドで同一タスクが多重複入（Concurrent Re-entry）してしまい、タイム・オブ・チェック〜タイム・オブ・ユース（TOCTOU）の並行競合が発生していた。

---

## 4. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis
- **CWE-362 (Race Condition) / CWE-662 (Improper Synchronization)**:
  - 状態遷移がコンテキスト静止化よりも先行することで、2つのスレッドが同一タスクコンテキスト（スタック、TLS、エスケープ継続）に並行アクセスし、データ破壊やセグメンテーションフォールトを引き起こす。
  - **対策**: スケジューラがタスク境界を脱出し、`task-state` を `waiting` に更新した後の post-boundary hook で状態復帰 CAS を行うことで、競合窓を完全に 0 にする。
- **CWE-843 (Type Confusion)**:
  - `task-resident-set!` は boolean または 1 引数 procedure（引数: `task`）のみを受け入れ、不正な型の代入を静的・動的ガードで排除する。
- **Lost Wakeup / Signal Starvation 防止**:
  - ループを抜けてからフックが呼ばれるまでの間に到着したシグナルは `running_notified` として記録され、フック実行時に即座に `scheduled` へ遷移してスケジューラに再投入されるため、シグナルの取りこぼしが 100% 発生しない。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/798-fix-supervisor-idle-state-transition-race`

### 1. `task-resident` へのフック機能統合 (`channel.scm`)
- `(task-resident-set! t val)`:
  - `val` が boolean（`#t`, `#f`）または procedure であることを検証（CWE-843）。
  - `%task-resident-box` に格納。
- `(task-resident? t)`:
  - 格納値が `#f` でなければ `#t` を返却。
- `(task-resident-hook t)`:
  - 格納値が procedure であればその手続きを返却、それ以外は `#f`。

### 2. スケジューラにおける脱出後フック呼び出し (`scheduler.scm`)
- `scheduler-execute-task!` の `task-resident?` 処理部：
  ```scheme
  (if (task-resident? ctx)
      (begin
        (if (not (eq? (task-state ctx) 'terminated))
            (task-state-set! ctx 'waiting))
        (let ((hook (task-resident-hook ctx)))
          (if (procedure? hook)
              (hook ctx)
              #t))
        res)
      (begin
        (task-exit! ctx 'normal)
        res))
  ```

### 3. Supervisor 側の遅延アイドル復帰と安全な再スケジュール (`supervisor.scm`)
- `%supervisor-post-drain-hook!` の実装:
  ```scheme
  (define (%supervisor-post-drain-hook! sup sup-task)
    (let ((box (%supervisor-enqueued-box sup)))
      (let retry ()
        (let ((cur (atomic-ref box)))
          (cond
            ;; 境界脱出中にシグナルが到着していた場合：即座に再スケジュール
            ((eq? cur 'running_notified)
             (atomic-set! box 'scheduled)
             (task-state-set! sup-task 'ready)
             (%supervisor-enqueue-child! sup sup-task)
             #t)
            ;; 通常時：running -> idle へ CAS
            ((eq? cur 'running)
             (if (atomic-cas! box 'running 'idle)
                 #t
                 (retry)))
            (else #t))))))
  ```
- `make-supervisor`:
  - `sup-task` に対して `(task-resident-set! sup-task (lambda (task) (%supervisor-post-drain-hook! sup task)))` を設定。
- `%supervisor-drain-loop!`:
  - スケジューラ経由（引数 `defer-idle?` が `#t`）の場合は `box` を `'idle` に戻さずにループを抜け、フックに遷移を委譲。直接呼び出し時は後方互換性のため即時 CAS を維持。

### 4. テストスイートの追加と検証 (`test_supervisor.scm`)
- Group 17:
  - 4 ワーカー高負荷マルチスレッドスケジューラ上で Supervisor を稼働。
  - 10 個以上の子タスクを非同期かつ超高速に連続クラッシュ（各タスク複数回クラッシュ）させる。
  - Supervisor タスクの同時実行数カウンタが常に最大 1 であり、二重起動やコンテキスト競合が皆無であることを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `task-resident-set!` がプロシージャを安全に保持でき、`task-resident?` が既存のコードと完全互換であること。
- [x] `scheduler-execute-task!` において、タスク境界脱出および `waiting` 状態設定後に post-boundary hook が確実に実行されること。
- [x] `%supervisor-drain-loop!` のスケジューラ経由実行時に、`idle` 復帰が境界脱出後フックへ遅延委譲されること。
- [x] 脱出処理中にシグナルが到着した場合（`running_notified`）に、安全に `scheduled` へ再スケジュールされること（Lost Wakeup 防止）。
- [x] `make -C ulisp test_supervisor` が 100% PASS すること（203 passed, 0 failed）。
- [x] `make -C ulisp test_scheduler`, `make -C ulisp test_preemption`, `make -C ulisp bench_concurrency_gate` が 100% PASS すること。
- [x] 相対パス規約が 100% 遵守されていること（絶対パス 0 件）。

---

## 7. 検証結果サマリー
1. **単体テスト**:
   - `test_supervisor.scm`: 203 / 203 passed (100% PASS)
   - `test_scheduler.scm`: 201 / 201 passed (100% PASS)
   - `test_preemption`: 92 / 92 passed (100% PASS)
2. **ベンチマークゲート**:
   - Throughput: 1,090,337 tasks/sec (DoD >1,000,000 tasks/sec 達成)
   - Spawn Time: 67 ms (DoD <250 ms 達成)
   - Performance Regression Audit: PASS (Baseline 比 +1.0%)
3. **並行性・安全性検証**:
   - 4 ワーカー環境での連続バーストクラッシュ（24 回）下で、Supervisor タスクの同時実行数 `max-active-workers` が常に `<= 1` を維持。
   - TOCTOU 競合窓（Race Condition Window）が完全解消され、CWE-362（データ競合）および CWE-662（同期不備）を根本から防止。
