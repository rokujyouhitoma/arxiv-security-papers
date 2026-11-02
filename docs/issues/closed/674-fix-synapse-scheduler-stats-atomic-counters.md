---
ID: 674
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] スケジューラ統計カウンタのアトミック化による並行終了判定の不整合・ハング防止 (ID: 674)

## 1. 概要 / Summary
`ulisp/runtime/concurrency/scheduler.scm` において、タスクの生成累計数（`tasks-spawned`）および完了累計数（`tasks-completed`）のインクリメント処理が通常の Scheme ベクタに対する非アトミックな更新で行われていた。
このため、マルチコア環境や並行ワーカー実行下でカウントのロスト（Lost Update, CWE-362）が発生し、スケジューラの完了待機ループ（`scheduler-run-until-done` / `%scheduler-run-loop`）が永久ハング（CWE-835）または実行中タスクの放置による早期終了（CWE-662）を引き起こす致命的な不具合を根本解消した。

### 再現手順 / Steps to Reproduce
1. 複数ワーカースレッド（4〜8ワーカー以上）を起動した状態で、短命なマイクロタスクを大量（数万〜10万個）に投入する。
2. `(scheduler-run! sched)` で全タスクの完了を待機する。
3. `tasks-spawned` や `tasks-completed` の並行更新競合により、全タスクの処理が完了しているにもかかわらず `(>= tasks-completed tasks-spawned)` が成立せず永久ループする、あるいはタスク実行中に誤って早期脱出する事象が発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / uLisp Concurrency Runtime (Native AOT & Dual-Mode Interpreter)
- File: [ulisp/runtime/concurrency/scheduler.scm](../../../ulisp/runtime/concurrency/scheduler.scm)

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #645 (並行 CI ハーネス)](645-implement-synapse-multicore-concurrency-ci-harness.md)
  - [Issue #671 (コルーチン ID アトミック化)](671-fix-synapse-coroutine-id-atomic-allocation.md)
  - [Issue #672 (Epoch 原子的進行保証)](672-fix-synapse-epoch-advance-atomic-return-race.md)
  - [Issue #673 (グローバルアトミック Task ID 採番器)](673-implement-synapse-global-atomic-task-id-allocator.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../../ulisp/runtime/concurrency/scheduler.scm)
- [x] [ulisp/lib/ulisp/concurrency/scheduler.sld](../../../ulisp/lib/ulisp/concurrency/scheduler.sld)
- [x] [tests/concurrency/test_scheduler.scm](../../../tests/concurrency/test_scheduler.scm)
- [x] [tests/concurrency/concurrency_harness.scm](../../../tests/concurrency/concurrency_harness.scm)

---

## 4. 根本原因分析 (RCA) & セキュリティ脅威分析
1. **根本原因**:
   `scheduler.scm` の 129〜133行目および 193〜199行目の実装：
   ```scheme
   (define (%make-scheduler-stats)
     (let ((s (make-vector 2)))
       (vector-set! s 0 0)
       (vector-set! s 1 0)
       s))
   ...
   (define (%scheduler-tasks-spawned-inc! sched)
     (let ((s (%scheduler-stats sched)))
       (vector-set! s 0 (+ (vector-ref s 0) 1))))

   (define (%scheduler-tasks-completed-inc! sched)
     (let ((s (%scheduler-stats sched)))
       (vector-set! s 1 (+ (vector-ref s 1) 1))))
   ```
   `%scheduler-stats` は通常の Scheme ベクタ（`make-vector 2`）に生の整数を格納しており、複数の OS スレッド（ワーカースレッド群および外部プロデューサスレッド群）が同時に `(vector-ref s ...)` して `+ 1` した値を `vector-set!` していた。
   アトミックなハードウェア命令（`atomic-fetch-add!` による `LOCK XADD`）を使用していなかったため、並行書き込み時に典型的な Lost Update（更新喪失）が発生し、真のタスク実行数との乖離が生じていた。

2. **セキュリティ脅威（STRIDE / CWE）**:
   - **CWE-362 (Race Condition / Concurrent Execution using Shared Resource with Improper Synchronization)**:
     非同期ワーカー間およびタスク投入スレッド間での非排他的カウンタ更新によるデータ破壊。
   - **CWE-835 (Loop with Unreachable Exit Condition / Infinite Loop / DoS)**:
     `completed` のカウントがロストして `spawned` に達しなくなり、スケジューラの完了待機ループ（`%scheduler-run-loop`）が終了不能となり CPU 100% の永久ハングを誘発。
   - **CWE-662 (Improper Synchronization on Shared Resource / Silent Task Loss)**:
     `spawned` のカウントロストにより、実際にはまだ実行待ちのタスクが存在するにもかかわらず `(>= completed spawned)` が早期成立してスケジューラが終了し、タスクの実行が打ち切られる。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 単一ワーカースレッドでのみタスク生成・完了を行う（マルチコア並行の無効化）。
* **恒久対策 (Permanent Fix)**:
  1. `%make-scheduler-stats` において、`spawned`（インデックス 0）および `completed`（インデックス 1）の格納スロットにそれぞれ独立した `<atomic-box>`（初期値 0）を格納する。
  2. `%scheduler-tasks-spawned-inc!` および `%scheduler-tasks-completed-inc!` を `(atomic-fetch-add! (vector-ref s 0/1) 1)` による原子的インクリメントへ置換する。
  3. `scheduler-tasks-spawned` および `scheduler-tasks-completed`（ならびにエイリアスの `scheduler-total-spawned`, `scheduler-total-completed`）の参照を `(atomic-ref (vector-ref s 0/1))` に統一する。
  4. 戻り値の型（fixnum）および外部公開 API の互換性を 100% 維持する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/674-scheduler-stats-atomic-counters`

### Step 1: `ulisp/runtime/concurrency/scheduler.scm` の修正
1. `%make-scheduler-stats`:
   ```scheme
   (define (%make-scheduler-stats)
     (let ((s (make-vector 2)))
       (vector-set! s 0 (make-atomic-box 0))
       (vector-set! s 1 (make-atomic-box 0))
       s))
   ```
2. アクセサとインクリメント手続きのアトミック化:
   ```scheme
   (define (scheduler-tasks-spawned sched)
     (atomic-ref (vector-ref (%scheduler-stats sched) 0)))

   (define (scheduler-tasks-completed sched)
     (atomic-ref (vector-ref (%scheduler-stats sched) 1)))

   (define (%scheduler-tasks-spawned-inc! sched)
     (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 0) 1))

   (define (%scheduler-tasks-completed-inc! sched)
     (atomic-fetch-add! (vector-ref (%scheduler-stats sched) 1) 1))
   ```
3. 終了待機ループ `%scheduler-run-loop` の二重判定箇所を整理し、常にアトミックに最新スナップショットを取得する。

### Step 2: `ulisp/lib/ulisp/concurrency/scheduler.sld` のエクスポート確認
1. `scheduler-tasks-spawned`, `scheduler-tasks-completed` を明示的に export リストに追記。

### Step 3: テストスイート拡充
1. `tests/concurrency/test_scheduler.scm`:
   - Group 3b を新設し、アトミックカウンタ単体検証（10,000 回並行インクリメント相当の不可分性・単調増加性アサーション）を追加。
   - 100,000 タスク耐久テスト（Group 5）での `scheduler-total-spawned` と `scheduler-total-completed` の完全一致（差分 0）アサーションを強化。
2. `tests/concurrency/concurrency_harness.scm`:
   - Scenario 4d（カオスジッター注入下でのスケジューラ統計アトミック性検証）を追加。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `%scheduler-stats` の `spawned` および `completed` が `<atomic-box>` で保護され、`atomic-fetch-add!` で不可分更新されること。
- [x] 外部公開手続き（`scheduler-tasks-spawned`, `scheduler-tasks-completed` 等）が常に正確な fixnum を返却すること。
- [x] `make -C ulisp test_scheduler` が全件 PASS すること。
- [x] `make -C ulisp test_concurrency_harness`（100 反復）において、スケジューラ統計の不整合・ハングが 0 件であること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

