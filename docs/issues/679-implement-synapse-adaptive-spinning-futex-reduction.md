---
ID: 679
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 適応的スピン (Adaptive Spinning) による Futex システムコールの削減とタスク起床遅延の極小化 (ID: 679)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、ワーカーのタスク枯渇時に即座に `SYS_futex` (wait) システムコールを発行すると、カーネル空間へのコンテキストスイッチと復帰遅延（数 μs）が発生し、後続タスク到着時の起床ジッター要因となる。
本 Issue では、`SYS_futex` に突入する前に x86-64 `PAUSE` 命令 (`rep nop`) を用いた短時間の適応的スピン（Adaptive Spinning）フェーズを導入し、マイクロ秒オーダーで連続到着するタスクのシステムコール発行ゼロでの即時ディスパッチを実現する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Phase 7 / Phase 8)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #676: Linux SYS_futex park/unpark](closed/676-implement-synapse-futex-park-unpark-primitives.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/futex.s](../../ulisp/runtime/concurrency/futex.s) (PAUSE 命令ループ・適応的スピンアセンブリプリミティブ `%sys-futex-spin-pause`)
- [ ] [ulisp/runtime/concurrency/futex.scm](../../ulisp/runtime/concurrency/futex.scm) (`futex-wait-adaptive!`, スピンリトライ上限・動的バックオフ制御)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) (ワーカー待機ループへの適応的スピン統合)
- [ ] [tests/concurrency/test_futex.scm](../../tests/concurrency/test_futex.scm) (適応的スピン動作検証およびフォールバック試験)
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/679-synapse-adaptive-spinning-futex-reduction`

1. **アセンブリ低レベルスピン命令の追加**:
   - `futex.s` に CPU パイプラインストールを軽減する `rep; nop` (PAUSE) 命令を反復実行する `%sys-cpu-pause` または `%sys-spin-wait` を実装。
2. **適応的スピン待機ロジックの導入**:
   - ワーカーがデックおよびグローバルキューからタスクを取得できなかった際、固定回数（例: 64〜512 サイクル）の PAUSE スピンを行いながらキュー状態を監視。
   - スピン中にタスクが投入された場合は Futex システムコールをスキップして即座に実行へ復帰。
3. **指数バックオフとエネルギー効率の保証**:
   - スピン試行上限に達した後にのみ `SYS_futex` による省電力スリープ（Park）へ遷移。
   - システムコール発行率の大幅削減をベンチマークで実測。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `futex.s` に x86-64 PAUSE 命令を安全に呼び出す低レベルプリミティブが実装されていること。
- [ ] `futex-wait-adaptive!` または `scheduler.scm` のワーカー待機ループにおいて、短時間負荷時のシステムコール呼出が削減されること。
- [ ] 既存の並行テストスイート（`test_futex`, `test_scheduler`, `test_concurrency_harness`）が 100% PASS すること。
- [ ] ベンチマークにおいてタスク間レイテンシの極小化（P99 遅延の低減）が確認されること。
- [ ] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。

