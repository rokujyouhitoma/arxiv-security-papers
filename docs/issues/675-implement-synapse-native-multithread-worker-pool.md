---
ID: 675
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] Linux sys_clone ネイティブスレッド生成と CPU コアピニング (sched_setaffinity) による物理マルチコア並列実行エンジンの実装 (ID: 675)

## 1. 概要 / Summary
現在の Synapse M:N スケジューラ（`scheduler.scm`）は単一の OS スレッド上で各ワーカーを順番にステップ実行する時分割インターリーブ（協調的シミュレーション）にとどまっており、マルチコア CPU 環境において最大 1 コア（100%）しか使用できない制約がある。
Linux の `sys_clone` システムコールを用いて物理 CPU コア数と同数の独立した OS ネイティブスレッド（Worker Thread 0〜N-1）を起動し、`sched_setaffinity` により各スレッドを特定の CPU コアに 1:1 バインド（ピニング）する物理マルチコア並列実行エンジンを確立する。
これにより、各コアの独立した Chase-Lev Deque およびプロセスローカル・エフェメラルアリーナが真のハードウェア並列で稼働し、全 CPU コアを 100% 飽和させる極限スケーラビリティを達成する。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- 関連 Issue:
  - [Issue #630 (タスク独立エフェメラルアリーナ)](closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #634 (System V AMD64 Callee-saved コンテキストスイッチ)](closed/634-implement-synapse-callee-saved-context-switch.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #674 (スケジューラ統計カウンタのアトミック化)](closed/674-fix-synapse-scheduler-stats-atomic-counters.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [ulisp/runtime/concurrency/thread.scm](../../ulisp/runtime/concurrency/thread.scm)
- [ ] [ulisp/runtime/concurrency/thread.s](../../ulisp/runtime/concurrency/thread.s)
- [ ] [ulisp/lib/ulisp/concurrency/thread.sld](../../ulisp/lib/ulisp/concurrency/thread.sld)
- [ ] [ulisp/lib/ulisp/concurrency/scheduler.sld](../../ulisp/lib/ulisp/concurrency/scheduler.sld)
- [ ] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm)
- [ ] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/675-native-multithread-worker-pool`

1. **Linux `sys_clone` ネイティブスレッド起動アセンブリ (`thread.s`)**:
   - `CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM` フラグを指定したスレッド生成ルーチンを AMD64 アセンブリで実装。
   - 子スレッド用の独立したコールスタック（1MB バウンドスタック）の確保と初期化。
2. **CPU コアピニング (`sched_setaffinity`)**:
   - スレッド起動時に自身の Worker ID に対応する CPU コアマスクを設定し、`SYS_sched_setaffinity` を呼び出してコアへ固定。
   - キャッシュマイグレーション（L1/L2 キャッシュ汚染）を排除。
3. **並列スケジューラループ (`scheduler.scm`)**:
   - `scheduler-start-native-workers!` 手続きを新設し、ワーカーごとに独立した実行ループを各スレッドで常時駆動。
   - メインスレッドはタスク投入および終了待機・モニタリングを担当。
4. **テスト検証**:
   - マルチコア環境下での並行タスク実行（8〜16スレッド並列）で、全スレッドが同時に進捗することを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `sys_clone` により複数の OS スレッドが正常に起動し、並列にタスクを消化できること。
- [ ] `sched_setaffinity` により各ワーカーが指定の CPU コアに固定されること。
- [ ] 複数ワーカー並列実行下で Chase-Lev Deque のスティーリングが競合・破損なく動作すること。
- [ ] `make -C ulisp test_scheduler` および新設テストが 100% PASS すること。
- [ ] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。
