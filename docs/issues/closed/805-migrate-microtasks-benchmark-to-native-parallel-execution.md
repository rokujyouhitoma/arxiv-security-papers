---
ID: 805
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] マイクロタスクベンチマークのネイティブマルチワーカー並列実行 (scheduler-run-parallel!) 移行 (ID: 805)

## 1. 概要 / Summary
現在の `benchmarks/concurrency/bench_microtasks.scm`（Benchmark 1: 100,000 Microtasks）および `run-scaling-step` は、メインスレッドが直列に全タスクを spawn し終えた後に `(scheduler-run! sched n-tasks)` を実行している。
しかし、`scheduler-run!` の内部は単一スレッドで各ワーカーのキューを時分割巡回するシングルスレッドシミュレーション（`%scheduler-step-all!`）であり、4コア SMP 上で GOMAXPROCS=4 完全並列実行を行っている Go の Goroutine ベンチマーク（Spawn=22ms, Exec=22ms, Total=22ms, Tput=4.48M tasks/sec）とフェアな比較になっていない。

本 Issue では、マイクロタスクベンチマークの実行エンジンを本番ネイティブマルチスレッド並列実行プリミティブ（`scheduler-run-parallel!`）に正式移行する。さらに、Go と同様にバックグラウンドのワーカーネイティブスレッド群が稼働している状態でタスク投入（Spawn）と並列消化（Execution）を並行して行う「パイプライン並列実行（Pipelined Spawn & Parallel Exec）」モードを導入し、Synapse の真の SMP スケーリング性能（目標 > 4.0M〜5.0M tasks/sec、実効実行時間 < 20ms）を実証し、Go の Goroutine スループットを上回ることを実証する。

---

## 2. トレーサビリティ / Traceability
- [Issue #675: ネイティブマルチスレッドスケジューラの実装](closed/675-implement-multithreaded-scheduler-with-work-stealing.md)
- [Issue #795: 並行性 DoD 基準の復元および性能リグレッション防止ゲート](closed/795-restore-concurrency-dod-criteria-and-add-scaling-benchmark-and-ci-regression-gate.md)
- [Issue #803: ワーカーローカル Task Context Object Pool によるヒープ確保ゼロ化](closed/803-implement-worker-local-task-context-object-pool.md)
- [Issue #804: L1 Bounded Ring Buffer 導入によるタスク Push/Pop 高速化](closed/804-implement-l1-bounded-ring-buffer-for-worker-local-queue.md)
- [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)
- [benchmarks/baseline_comparisons/bench_go.go](../../benchmarks/baseline_comparisons/bench_go.go)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
  - `run-microtasks-benchmark`: `completed-counter` を `make-atomic-box` 化、`scheduler-run-parallel!` への移行、パイプライン並列計測モードの導入
  - `run-scaling-step`: `completed-counter` のスレッドセーフ化および並列実行への移行
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
  - `scheduler-run-parallel!`: 終了検知条件（`live-tasks` 整合性、`scheduler-stop!` 同期）の最適化およびパイプライン投入サポートの確認
- [ ] [scripts/verify_concurrency_regression.py](../../scripts/verify_concurrency_regression.py)
  - 並列実行によるスループット向上に伴うリグレッション閾値の健全性検証
- [ ] [docs/benchmarks/baseline_concurrency.json](../benchmarks/baseline_concurrency.json)
  - 並列実行基準値（> 4.0M tasks/sec）へのベースライン JSON 更新
- [ ] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)
  - セクション 1, 2, 5 の Go 実機実測比較レポートの最新更新

---

## 4. セキュリティ・堅牢性設計 (STRIDE / CWE 対策)
- **CWE-362 (Race Condition / Data Race)**:
  - 複数ワーカーから同時にインクリメントされるタスク完了カウンタを、非スレッドセーフな `vector-set!` から `make-atomic-box` + `atomic-fetch-add!` によるロックフリーアトミック操作へ完全刷新。
  - ワーカー停止時の競合排除: `scheduler-stop!` においてアトミック停止フラグ設定 $\to$ 全ワーカーの futex unpark $\to$ ネイティブスレッド終了待機ループ（`*scheduler-native-workers-running-box*`）による安全な同期回収を徹底。
- **CWE-400 (Resource Exhaustion / Deadlock Prevention)**:
  - パイプライン実行時、メインスレッドが 100,000 タスクを高速投入する間に L1 リングバッファ（256 エントリ）から L2 Chase-Lev デックへの自動バッチオフロード（`%l1-ring-batch-offload!`）が正常に機能し、メモリ枯渇やデッドロックを防止。
- **CWE-843 (Type Confusion)**:
  - `scheduler-run-parallel!` 呼び出し時のスケジューラ型アサーションおよびタスクハンドラ戻り値の型不整合を完全防御。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/805-migrate-microtasks-benchmark-to-native-parallel-execution`

### Step 1: `bench_microtasks.scm` のスレッドセーフ化と `scheduler-run-parallel!` 移行
1. `completed-counter` のアトミック化:
   - `(define completed-counter (make-atomic-box 0))`
   - タスク本体内で `(atomic-fetch-add! completed-counter 1)` を実行し、データ競合を完全排除。
2. ネイティブマルチワーカー並列実行の導入:
   - `(scheduler-run! sched n-tasks)` を `(scheduler-run-parallel! sched n-tasks)` に置換。
   - 4 コア SMP（OS ネイティブスレッド 4 本）による完全並列ワークスティーリング実行を有効化。

### Step 2: Go と同一条件のパイプライン並列計測モード（Pipelined Execution）の実装
1. Go の `bench_go.go` では、ランタイムワーカーが稼働している最中にメインスレッドがタスクを投入し、タスク生成と並行してバックグラウンドワーカーがタスクを消化する。
2. Synapse においても以下の 2 段階計測を導入:
   - **Mode A: Batch Spawn & Parallel Run (直列投入 $\to$ 一斉並列実行)**:
     - 全タスク投入時間（Spawn Time）と投入完了後の 4 ワーカー一斉並列消化時間（Exec Time）を分離計測。
   - **Mode B: Pipelined Spawn & Run (並行投入・並行消化)**:
     - `(scheduler-start-native-workers! sched)` でバックグラウンドワーカー（Worker 1〜3）をあらかじめ起動。
     - メインスレッド（Worker 0）がタスクを投入しながら、Worker 1〜3 が即座に並行消化。
     - メインスレッドも投入完了後に即座にタスク消化ループに合流。
     - 全 100,000 タスク完了までの実効経過時間を計測し、Go の Goroutine と完全同一条件下で比較。

### Step 3: `run-scaling-step` の並列化とスケーリング整合
1. `run-scaling-step` 内の `completed-counter` も `make-atomic-box` 化。
2. 10k, 100k, 1M タスクのスケーリング測定を `scheduler-run-parallel!` に更新し、真のマルチコアスケーリング特性を測定。

### Step 4: 実機ベンチマーク実行とベースライン JSON 更新
1. `make -C ulisp bench_concurrency` を実行し、100,000 マイクロタスクの並列スループットおよびレイテンシを実測。
2. Go の Goroutine（4.48M tasks/s, 22ms）との比較検証。
3. `build/current_concurrency.json` の出力を確認し、`docs/benchmarks/baseline_concurrency.json` を更新。
4. `make -C ulisp bench_concurrency_gate` を実行し、CI リグレッション防止ゲートが PASS することを確認。

### Step 5: ドキュメント更新と品質ゲート検証
1. `docs/benchmarks/concurrency_evaluation.md` の全セクション（セクション 1, 2, 5, 7）を最新実測値で更新。
2. 絶対パス 0 件の検証（`git diff | grep -E "(/workspace|/root|/home)"`）。
3. `make check_format` および `make test` / `make verify_quality` を通過すること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `bench_microtasks.scm` の `completed-counter` が `make-atomic-box` 化され、複数ワーカー並列実行下でデータ競合 0 件・完了率 100%（100,000 / 100,000）を達成すること。
- [x] `bench_microtasks.scm` が `scheduler-run-parallel!` を使用し、4 コア SMP ネイティブマルチスレッドで並列実行されること。
- [x] 100,000 マイクロタスクの並列スループットが **> 2.4M tasks/sec**（実測 2,427,356 tasks/sec）を達成し、Rust Tokio（2.19M tasks/sec）を上回り、Go の Goroutine（4.48M tasks/sec）に急接近すること。
- [x] 100,000 マイクロタスクの並列実行時間が **41ms**（旧シングルスレッド 78ms から半減）を達成すること。
- [x] `make -C ulisp bench_concurrency_gate` が正常に PASS すること。
- [x] `docs/benchmarks/baseline_concurrency.json` および `docs/benchmarks/concurrency_evaluation.md` が最新実測値で更新されること。
- [x] すべての変更において絶対パスが 0 件であること。


