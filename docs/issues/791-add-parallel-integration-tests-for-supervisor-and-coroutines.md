---
ID: 791
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 並行スケジューラ (scheduler-run-parallel!) 上での Supervisor・コルーチン・同時子異常終了の結合テスト整備 (ID: 791)

## 1. 概要 / Summary
Synapse 並行性ランタイムおよび Erlang/OTP 型 Supervision Tree の信頼性を極限まで高めるため、マルチ OS スレッド環境（`scheduler-run-parallel!`）下における Supervisor、コルーチン型子タスク、および複数子タスクの同時異常終了（カオスバーストシナリオ）の統合動作を検証する包括的な並行結合テストスイートを整備・拡充する。

現状、`test_supervisor.scm` における障害復旧テストは単一スレッドループ（`scheduler-run!`）に限定されており、4 ワーカー以上のネイティブスレッド並行実行時における OS スレッド間のワークスチール、複数コアからの同時 panic 通知（DOWN シグナル）のキューイング競合、および中断状態にあるコルーチン型子タスクの強制停止・再起動ライフサイクルがマルチスレッド自動テストで網羅されていない。
さらに、CI カオスハーネス（`tests/concurrency/concurrency_harness.scm`）内には、Issue #741 / #743 / #789 以前の古い手動ポーリング方式（`supervisor-poll-down-signals!` および手動 `scheduler-spawn!`）を用いた旧態依然のコードが残存しており、ランタイム本来の自律的耐障害性（自動タスクディスパッチ）がカオス環境下で検証されていない。

本 Issue では、`test_multithread_scheduler.scm` にマルチスレッド Supervisor テストグループ（Group 10 & 11）を新設するとともに、カオスハーネスを近代化し、並行性ランタイム全体の耐障害性とゼロリーク・デッドロックフリーを実証する。

---

## 2. セキュリティ脅威分析 / Threat Model & Security Impact
- **対象脆弱性**:
  - **CWE-362 / CWE-662**: Race Condition / Concurrent Execution using Shared Resource with Improper Synchronization - 複数 OS スレッドワーカー上で動作する子タスクが同時に panic した場合、同一 Supervisor の受信メールボックスやスケジューラ投入フラグ（`supervisor-enqueued-state`）に対して並行アクセスが発生し、メッセージ消失や重複エンキュー、状態不整合が生じる脅威。
  - **CWE-772**: Missing Release of Resource after Effective Lifetime - `context-yield!` により中断状態にあるコルーチン型タスクが障害や強制停止を受けた際、タスクコンテキストや関連アリーナが未解放のまま孤立し、メモリリークや未回収リソースによる OOM に至る脅威。
  - **CWE-835 / CWE-400**: Deadlock / Starvation (Infinite Loop / Resource Exhaustion) - 複数スレッド間でのワークスチールやタスク再投入のロック競合により、スケジューラワーカーがデッドロックに陥り、サービス全体がハングアップする脅威。
- **STRIDE 分類**:
  - **Denial of Service (DoS)**: 並行障害発生時に Supervisor が正常に回復できず、ワーカースレッドが停止またはハングアップする。
- **セキュリティ保証目標**:
  - 複数 OS スレッド環境において、いかなるバースト障害や中断タスクの異常終了が発生しても、デッドロック・データ競合・メモリリークを発生させることなく、確定的に全子タスクが再起動され正常稼働状態に回復することを保証する。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm): Group 10（マルチスレッド同時バーストクラッシュ自動復旧テスト）および Group 11（マルチスレッドコルーチン子タスクの中断・障害復旧テスト）の追加。
- [ ] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm): Scenario 4e（`run-scenario-supervisor-fault-isolation!`）の自動スケジューリングモード（`supervisor-start! sup sched #t`）への全面刷新、手動ポーリング撤去。
- [ ] [ulisp/runtime/concurrency/supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm): 並行環境における Supervisor 内部状態の整合性確認（必要に応じた微小アトミックガードの補強）。
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm): 並行スケジューラにおける Supervisor タスクおよびコルーチンタスクのスケジューリング挙動の検証。

---

## 4. 根本原因分析と技術的課題 / RCA & Technical Challenges
1. **マルチスレッド結合テストの網羅性不足**:
   - Issue #788（メールボックス空判定での誤正常終了防止）および Issue #789（同時クラッシュ時の重複投入抑止）の修正は `test_supervisor.scm` で単一スレッド検証されたが、実 OS スレッド（`scheduler-run-parallel!`）環境でのマルチワーカー競合耐性の検証が未実施であった。
2. **コルーチンタスクの中断状態障害復旧の未検証**:
   - コルーチン型タスクが `yield` して待機している間に、Supervisor や他タスクから終了シグナルが送出された場合、または再開時に例外が伝播した場合の Supervisor 再起動動作が未検証であった。
3. **カオスハーネスの旧式実装残存**:
   - `concurrency_harness.scm` 内のシナリオ 4e が `(supervisor-poll-down-signals! sup)` と手動 `(scheduler-spawn! sched t-child-2 0)` を直接呼び出す古いプロシージャとなっており、自律分散スケジューリングモードの耐障害性が 100 反復ジッター試験でテストされていなかった。

---

## 5. 改善方針と設計 / Workaround & Architectural Design
* **暫定対処 (Workaround)**:
  - 単一スレッドでのみ Supervisor を実行し、マルチスレッド環境での自動タスク再起動を回避する（並列性能が著しく低下）。
* **恒久対策 (Permanent Fix)**:
  1. `test_multithread_scheduler.scm` に 4 OS スレッドワーカーを用いた本格的な Supervisor 結合テストを組み込む。
     - **テストケース 1 (Group 10)**: 8 個の子タスクを抱える Supervisor を 4 ワーカー上で稼働させ、全子タスクをマルチスレッドから一斉に同時 panic させる。Supervisor の 4 状態遷移（`idle` → `scheduled` → `running` → `running_notified`）が機能し、二重投入なく全 8 タスクが整然と再起動されることを実証。
     - **テストケース 2 (Group 11)**: コルーチン型子タスク（`make-coroutine-context`）が 1 回 `yield` して中断している最中に、外部からの異常終了（`task-exit!`）または再開時例外を発生させ、Supervisor が DOWN を受けてクリーンに新規コルーチンとして再起動することを実証。
  2. `concurrency_harness.scm` の `run-scenario-supervisor-fault-isolation!` を、`supervisor-start! sup sched #t` を用いた自律スケジューリング方式に改修し、手動処理を全廃。
  3. CI ハーネス 100 反復カオスジッター試験（`test_concurrency_harness`）で 100% PASS を達成する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/791-parallel-supervisor-coroutine-integration-tests`

### Step 1: `test_multithread_scheduler.scm` への結合テスト追加
- **Group 10**:
  - `make-supervisor`（one_for_one 戦略, max-restarts 30, window 1000）。
  - 8 個の子タスク（`permanent`）を登録し、`supervisor-start! sup sched #t` で 4 ワーカー並行スケジューラへ投入。
  - 4 個の OS スレッドから 8 個の子タスクに対して一斉に `task-exit! '(panic . parallel_burst)` を送出。
  - `scheduler-run-parallel!` を実行し、全 8 子タスクが正確に 1 回ずつ再起動（初期起動 + 再起動 = 計 16 回）され、新しい TID が割り当てられ、Supervisor が `'waiting` 状態へ安全に戻ることをアサート。
- **Group 11**:
  - コルーチン型タスクを子タスクとする Supervisor を構築。
  - 子タスクが起動後に 1 回 `context-yield!` して待機状態へ遷移。
  - 別スレッドから当該子タスクに `task-exit! '(panic . coro_crashed_while_yielded)` を送出。
  - `scheduler-run-parallel!` 下で Supervisor が検知し、新規コルーチンとして再起動・再実行されることを検証。

### Step 2: `concurrency_harness.scm` のシナリオ 4e の近代化
- `run-scenario-supervisor-fault-isolation!` を修正:
  - `(supervisor-start! sup sched #t)` でスケジューラ自動登録。
  - 手動の `(supervisor-poll-down-signals! sup)` および `(scheduler-spawn! sched t-child-2 0)` を削除。
  - `scheduler-run! sched` を呼ぶだけで、子タスクのクラッシュ・DOWN ハンドリング・再起動・新子タスクの完了までが自動完結することを検証。

### Step 3: 全並行テストスイートおよび品質ゲート検証
- `make -C ulisp test_multithread_scheduler`
- `make -C ulisp test_supervisor`
- `make -C ulisp test_concurrency_harness`
- `make -C ulisp test_concurrency`
- `make verify_quality`

---

## 7. 完了条件 / Success Criteria (DoD)
- [ ] `test_multithread_scheduler.scm` に Group 10（マルチスレッド同時バーストクラッシュ自動復旧）が追加され、4 ワーカー並行環境で 100% PASS すること。
- [ ] `test_multithread_scheduler.scm` に Group 11（マルチスレッドコルーチン子タスクの中断・障害復旧）が追加され、4 ワーカー並行環境で 100% PASS すること。
- [ ] `concurrency_harness.scm` の Scenario 4e が自動スケジューリングモードに近代化され、手動ポーリング呼び出しが全廃されていること。
- [ ] CI カオスハーネス 100 反復ジッター試験（`test_concurrency_harness`、計 13,600 アサーション）が 0 失敗で完全 PASS すること。
- [ ] 既存の全並行テスト（`test_scheduler`, `test_multithread_scheduler`, `test_supervisor`, `test_preemption`）がリグレッションなく PASS すること。
- [ ] すべてのファイルリンクが相対パス（`../../...`）であり、絶対パスが 0 件であること。
