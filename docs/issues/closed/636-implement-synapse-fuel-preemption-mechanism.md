---
ID: 636
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] リダクション方式セーフポイント注入と協調的・強制的プリエンプション機構の実装 (ID: 636)

## 1. 概要 / Summary
[DSN-37] Phase 2 Task 2.3 に基づき、CPU バウンドな無限ループタスクによるコア占有・スタベーションを阻止する Erlang BEAM 方式のリダクション（Reduction / Fuel）セーフポイント注入・プリエンプション機構を実装した。
各タスクに実行計算予算（デフォルト 4096 リダクション）を付与し、セーフポイント通過ごとにデクリメントを行い、予算枯渇時に確実に CPU コアを解放（yield）・ローカルランキュー末尾へ再投入して次タスクへディスパッチさせる。

---

## 2. 背景と設計原則 / Background & Design Principles
- **Erlang BEAM 方式の決定論的プリエンプション**:
  OS シグナル（`SIGALRM` 等）による非同期割り込みは、メモリアロケーション中やアトミック操作中の非同期例外による状態破壊・デッドロック（CWE-362 / CWE-662）のリスクを孕む。これに対し、関数のプロローグやループバックエッジにリダクション減算・枯渇判定（セーフポイント）を配置するポーリング方式を採用することで、安全な境界でのみ確実に CPU を譲渡する。
- **ゼロアロケーション ＆ 高速セーフポイント判定**:
  セーフポイント判定 `(check-safepoint! task)` はループ反復ごとに実行されるため、ヒープ確保を一切行わない 0 アロケーションかつ数命令のレジスタ/直接メモリアクセスで完結させた。
- **スケジューラ連携 (`scheduler-yield!`)**:
  予算枯渇を検知した際、`scheduler-yield!` が予算をリセット（4096）し、プリエンプション回数（`task-exhaustion-count`）を記録した上で、タスク状態を `TASK_READY` としてローカル Deque またはスケジューラへ再エンキューし、直ちに次タスクへコンテキストを切り替える。

---

## 3. トレーサビリティ / Traceability
- **アーキテクチャ設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 7.2 節: リダクション方式セーフポイント注入による決定論的プリエンプション
    - 第 7.3 節: 極小スタック・コルーチンコンテキストスイッチ
    - 第 14.4 節: Phase 2 M:N スケジューラ ＆ 強プリエンプション Task 2.3
- **関連 Issue**:
  - [Issue #630: タスク独立型プロセスローカル・エフェメラルアリーナ](630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #631: 低レベルアトミック並行プリミティブ](631-implement-synapse-low-level-atomic-primitives.md)
  - [Issue #632: Michael-Scott ロックフリー FIFO キュー](632-implement-synapse-michael-scott-lockfree-queue.md)
  - [Issue #633: 線形所有権型 P2P チャネル](633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #634: Callee-Saved ネイティブコンテキストスイッチ](634-implement-synapse-callee-saved-context-switch.md)
  - [Issue #635: Chase-Lev ワークスティーリング スケジューラ](635-implement-synapse-work-stealing-scheduler.md)

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/runtime/concurrency/preempt.scm`: リダクション管理、セーフポイント判定、予算枯渇時 yield 処理
- `ulisp/lib/ulisp/concurrency/preempt.sld`: R7RS `(ulisp concurrency preempt)` ライブラリ定義
- `tests/concurrency/test_preemption.scm`: リダクション減算、プリエンプション回数追跡、無限ループ並行タスクスタベーション防止テストスイート

### 既存更新
- `ulisp/runtime/concurrency/scheduler.scm`: `<budgeted-task>` のディスパッチおよび実行連携フック
- `ulisp/Makefile`:
  - `test_preemption` ターゲットの追加
  - `test:` メインターゲットへの `test_preemption` 依存関係追加
  - `lint_sexpr` ターゲットへの追加
- `docs/issues/README.md`: Issue #636 ステータス更新（Completed）

---

## 5. 実装方針と成果 / Implementation & Results
Target Branch: `feat/636-reduction-preemption`

### 5.1 リダクションデータモデル設計 (`preempt.scm`)
1. **定数定義**:
   - `*default-reduction-budget* = 4096`: デフォルト計算予算
   - `*min-reduction-budget* = 1`: 最小計算予算
   - `*max-reduction-budget* = 1048576`: 最大計算予算（1M）
2. **`<budgeted-task>` レコード構造体**:
   - `id`: タスク一意識別子
   - `state-box`: タスク状態（`'ready`, `'running`, `'yielded`, `'completed`）
   - `reductions-box`: 残余リダクション保持ボックス（1 要素ベクタ）
   - `initial-budget`: 初期設定予算（4096）
   - `task-obj`: 実行対象（thunk / coroutine-context / task-context）
   - `exhaustions-box`: プリエンプション（枯渇）発生回数カウンタ（1 要素ベクタ）
3. **コア API**:
   - `(make-budgeted-task id task-obj [budget])`: 計算予算付きタスク生成
   - `(task-reductions obj)`: 残余リダクション取得（`<budgeted-task>` および `<task-context>` 両対応）
   - `(task-reductions-set! obj n)`: 残余リダクション設定（0〜上限クランプ）
   - `(task-initial-budget btask)`: 初期予算取得
   - `(task-exhaustion-count btask)`: プリエンプション発生回数取得
   - `(task-exhausted? btask)`: リダクションが 0 以下か判定
   - `(task-consume-reductions! btask [delta])`: リダクション消費（デフォルト delta = 1、負数アンダーフロー防止）
   - `(task-replenish! btask)`: リダクションを初期予算へ補充し、枯渇カウンタをインクリメント
   - `(check-safepoint! btask [on-exhaust-thunk])`: セーフポイント通過判定。残余があれば 1 減算、枯渇時は補充してコールバック呼び出し
   - `(safepoint-poll! btask)`: 素のセーフポイントポーリング
   - `(scheduler-yield! btask [sched])`: 予算リセット、状態更新、スケジューラ/ランキューへの再投入、コルーチンスイッチ
   - `(budgeted-task-execute! btask)`: タスクディスパッチ実行エンジン
   - `(budgeted-task-stats btask)`: 診断情報辞書取得

### 5.2 セキュリティガード (CWE 対策)
- **CWE-190 (整数オーバーフロー/アンダーフロー)**:
  - 負の計算予算、0 以下の予算指定、上限値（1M）超過の入力ガードおよびアンダーフロー抑止。
- **CWE-400 / CWE-834 (リソース枯渇 / 無限ループによるスタベーション)**:
  - CPU バウンドなビジーループタスクであっても、4096 反復以内に強制 yield が発生し、同居する他タスクに確実に CPU 時間を配分。
- **CWE-843 (型混同)**:
  - レコード型述語ガード、および不正なオブジェクトが渡された際の即時エラー送出。

---

## 6. テスト結果 / Test Results (`tests/concurrency/test_preemption.scm`)

```console
=======================================================
 Starting Reduction Safepoint & Preemption Test Suite (#636)
=======================================================
--- Group 1: Reduction Accounting & Task State Accessors ---
PASS: default task satisfies budgeted-task?
PASS: 100-budget task satisfies budgeted-task?
PASS: fixnum is not budgeted-task?
PASS: raw vector is not budgeted-task?
PASS: t-def id is 1
PASS: t-100 id is 2
PASS: default initial budget is 4096
PASS: custom initial budget is 100
PASS: initial remaining reductions equal initial budget
PASS: custom remaining reductions equal 100
PASS: initial exhaustion count is 0
PASS: initial task state is 'ready
PASS: fresh task is not exhausted
PASS: task-state-set! transitions state to 'running
PASS: task-reductions-set! updates reductions
PASS: budgeted-task-stats returns non-empty list
PASS: stats id is 1
PASS: stats initial-budget is 4096
PASS: stats remaining reductions is 2000
--- Group 2: Reduction Consumption & Replenishment ---
PASS: task-consume-reductions! default 1 decr to 9
PASS: task-consume-reductions! delta 4 decr to 5
PASS: task-reductions reflects 5 remaining
PASS: task not yet exhausted at 5
PASS: consuming exact 5 reductions leaves 0
PASS: task is exhausted when reductions reaches 0
PASS: underflow consumption clamps to 0
PASS: task remains exhausted after underflow
PASS: task-replenish! resets reductions to initial budget
PASS: task-reductions is 10 after replenish
PASS: task-exhaustion-count is incremented to 1
PASS: task is no longer exhausted after replenish
PASS: consecutive replenish increments exhaustion count to 2
--- Group 3: Safepoint Polling & Preemption Callback ---
PASS: tick 1 returns #t (4 remaining)
PASS: tick 2 returns #t (3 remaining)
PASS: tick 3 returns #t (2 remaining)
PASS: tick 4 returns #t (1 remaining)
PASS: callback not triggered before exhaustion
PASS: callback triggered exactly on 5th tick
PASS: task exhaustion count is 1
PASS: task-reductions automatically replenished to 5
PASS: 4096-budget task triggered exact 1 callback in 4096 ticks
PASS: task exhaustion count is 1 after 4096 ticks
PASS: total 5 preemption callbacks after 20,480 ticks
PASS: task exhaustion count is exactly 5
--- Group 4: Scheduler Integration & Starvation Freedom ---
PASS: Task B was NOT starved and completed successfully
PASS: Task A made computational progress
PASS: Task A incurred multiple preemptive yields
--- Group 5: Coroutine Cooperative Preemptive Context Switching ---
PASS: initial coro state is 'ready
PASS: coro ran 10 iterations on step 1
PASS: coro state transitioned to 'yielded on exhaustion
PASS: coro incurred 1 exhaustion
PASS: coro ran 20 cumulative iterations on step 2
PASS: coro state is 'yielded on step 2
PASS: coro incurred 2 exhaustions
PASS: coro ran 30 cumulative iterations on step 3
PASS: coro state is 'yielded on step 3
PASS: coro incurred 3 exhaustions
PASS: coro ran exactly 30 total loop iterations
PASS: coro state transitioned to 'completed
--- Group 6: 100,000 Reductions Safepoint Endurance ---
PASS: 100,000 ticks with 1000 budget produced exact 100 preemption callbacks
PASS: task exhaustion count is exactly 100
PASS: reductions correctly replenished to 1000
--- Group 7: Security & Boundary Guards ---
PASS: make-budgeted-task rejects non-integer id (CWE-843)
PASS: make-budgeted-task rejects budget 0 (CWE-190)
PASS: make-budgeted-task rejects negative budget (CWE-190)
PASS: make-budgeted-task rejects non-integer budget (CWE-843)
PASS: make-budgeted-task rejects oversized budget > 1M (CWE-400)
PASS: task-reductions rejects non-budgeted-task (CWE-843)
PASS: task-reductions-set! rejects non-budgeted-task (CWE-843)
PASS: task-reductions-set! rejects non-integer reductions (CWE-843)
PASS: task-consume-reductions! rejects non-budgeted-task (CWE-843)
PASS: task-consume-reductions! rejects negative delta (CWE-190)
PASS: task-replenish! rejects non-budgeted-task (CWE-843)
PASS: check-safepoint! rejects non-budgeted-task (CWE-843)
PASS: scheduler-yield! rejects non-budgeted-task (CWE-843)
PASS: budgeted-task-execute! rejects non-budgeted-task (CWE-843)
PASS: budgeted-task-stats rejects non-budgeted-task (CWE-843)
=======================================================
 Preemption & Reduction Safepoint Test Summary: 77 passed, 0 failed.
=======================================================
```

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/runtime/concurrency/preempt.scm` が新規作成され、`task-reductions`, `check-safepoint!`, `scheduler-yield!` 等の全 API が実装されていること
- [x] `ulisp/lib/ulisp/concurrency/preempt.sld` が作成され、R7RS ライブラリ仕様を満たしていること
- [x] 無限ループ `(let loop () (check-safepoint! btask ...) (loop))` を含むタスクが他タスクを餓死させずに並行実行できること
- [x] `task-exhaustion-count` がプリエンプション回数と厳密に一致してインクリメントされること
- [x] セーフポイント判定によるオーバーヘッドが 0 アロケーションかつ極小であること
- [x] `make -C ulisp test_preemption` が全アサーション PASS（0 failed）であること
- [x] `make -C ulisp test` のメインスイートに統合され、全テストが 100% 成功すること
- [x] 相対パスリンク規則を遵守し、絶対パスが 0 件であること
