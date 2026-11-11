---
ID: 805
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] マイクロタスクベンチマークのネイティブマルチワーカー並列実行 (scheduler-run-parallel!) 移行 (ID: 805)

## 1. 概要 / Summary
現在の `benchmarks/concurrency/bench_microtasks.scm`（Benchmark 1: 100,000 Microtasks）は、メインスレッドが直列に全タスクを spawn し終えた後に `(scheduler-run! sched n-tasks)` を実行している。
しかし、`scheduler-run!` の内部は単一スレッドで全ワーカーのキューを時分割巡回するシングルスレッドシミュレーションであり、4コア SMP 上で GOMAXPROCS=4 完全並列実行を行っている Go の Goroutine ベンチマーク（24ms）とフェアな比較になっていない。
本 Issue では、マイクロタスクベンチマークの実行エンジンを本番ネイティブマルチスレッド並列実行プリミティブ（`scheduler-run-parallel!`）に移行し、さらに Go と同様にタスク投入（Spawn）と並列消化（Execution）を並行して行うパイプライン計測モードを導入して、Synapse の真の SMP スケーリング性能（目標 > 4.5M〜5.0M tasks/sec、実行時間 < 15ms）を実証する。

---

## 2. トレーサビリティ / Traceability
- [Issue #675: ネイティブマルチスレッドスケジューラ](closed/675-implement-multithreaded-scheduler-with-work-stealing.md)
- [Issue #795: 並行性 DoD 基準の復元および性能リグレッション防止ゲート](closed/795-restore-concurrency-dod-criteria-and-add-scaling-benchmark-and-ci-regression-gate.md)
- [concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - `scheduler-run-parallel!` への切り替えと並行 Spawn 計測の導入
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - 並列実行時の終了検知とメトリクス集計の最適化
- [ ] [docs/benchmarks/baseline_concurrency.json](../benchmarks/baseline_concurrency.json) - 並列実行基準値への更新
- [ ] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - Go 実機実測との最新比較レポートの更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/805-migrate-microtasks-benchmark-to-native-parallel-execution`

1. `bench_microtasks.scm` において、`scheduler-run!` を `scheduler-run-parallel!` に更新。
2. ネイティブワーカー（Worker 1〜3）が稼働している状態で、メインスレッド（Worker 0）がタスクを投入しつつ並行してタスクを消化する実世界パイプライン型ベンチマークを実装。
3. Spawn 時間、実行時間、合計経過時間、および実効スループットの正確なナノ秒計測。
4. CI 性能リグレッションゲート（`make -C ulisp bench_concurrency_gate`）の閾値およびベースライン JSON の再整合。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `bench_microtasks.scm` が `scheduler-run-parallel!` で実行され、4コアマルチスレッドで並列動作すること。
- [ ] 100,000 マイクロタスクの実行時間が 20ms 以下を達成し、Go の Goroutine（24ms）を上回ること。
- [ ] スループットが 4.5M tasks/sec 以上を達成すること。
- [ ] `make -C ulisp bench_concurrency_gate` が正常に通過すること。

