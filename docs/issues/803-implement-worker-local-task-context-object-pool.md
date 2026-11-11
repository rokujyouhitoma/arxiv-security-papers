---
ID: 803
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] ワーカーローカル Task Context Object Pool によるヒープ確保ゼロ化と Spawn 高速化 (ID: 803)

## 1. 概要 / Summary
Synapse 並行処理基盤におけるマイクロタスク生成性能（現在 1.56M tasks/sec、Spawn 時間 40ms）を向上させ、Go の Goroutine（4.07M tasks/sec）を凌駕するため、タスクコンテキスト（`<task-context>`）の生成時におけるヒープ割り当て（`make-vector`）を完全撤廃する。
Go ランタイムにおける `gfget` / `gfput`（P ローカルな Free List キャッシュ）と同様に、各ワーカースレッド（TLS）に終了済みタスクコンテキストをキャッシュする固定長配列の **Task Context Object Pool (Free List)** を導入し、タスク Spawn 時は Free List から O(1) で即時再利用、タスク終了時は Free List へ即座に返却する。これにより 100,000 タスク生成時のヒープ割り当てを実質ゼロ（0 bytes）にし、L1/L2 キャッシュ局所性を極限まで高めて Spawn 時間を 40ms から 5ms 以下へ短縮する。

---

## 2. トレーサビリティ / Traceability
- [DSN-37: Synapse Dual-Plane Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Section 7.3 & 12.4
- [Issue #800: タスクコンテキスト atomic-box 遅延初期化](closed/800-implement-lazy-allocation-for-task-context-atomic-boxes.md)
- [Issue #801: 正常終了タスク向け Fast-path Termination](closed/801-implement-fast-path-for-normal-task-termination.md)
- [concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/context.scm](../../ulisp/runtime/concurrency/context.scm) - Task Context プール管理・リセット・再利用プリミティブの実装
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - `scheduler-spawn!` におけるワーカーローカルプールからの取得
- [ ] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `%task-fast-normal-termination!` におけるプールへの返却
- [ ] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm) - オブジェクトプール動作・リサイクル整合性テスト
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - Spawn レイテンシ・アロケーション削減効果の測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/803-implement-worker-local-task-context-object-pool`

1. ワーカーごとに固定長（例: 256〜512 エントリ）の Task Context キャッシュバッファを確保。
2. `scheduler-spawn!` において、プールに空きがある場合はヒープ割り当てを行わず、既存コンテキストのフィールド（TID、クロージャ、状態、reductions）を上書きして再利用。
3. タスク終了（`%task-fast-normal-termination!`）時に、コンテキストのメタ情報等をクリーンアップしてワーカーローカルプールに返却。
4. プール枯渇時はフォールバックとして `make-task-context` を呼び出す。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 各ワーカーに Task Context Pool が導入され、タスク再利用が O(1) で動作すること。
- [ ] 100,000 タスク実行時の GC ヒープ割り当て回数が大幅に削減（> 90% 削減）されること。
- [ ] 100,000 タスクの Spawn 時間が 40ms から大幅に短縮（目標 < 15ms）されること。
- [ ] 既存の並行性テストスイート（`test_scheduler`, `test_channel`, `test_multithread_scheduler`）が全件 PASS すること。

