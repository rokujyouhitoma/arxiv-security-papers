---
ID: 679
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 適応的スピン (Adaptive Spinning) による Futex システムコールの削減とタスク起床遅延の極小化 (ID: 679)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）において、ワーカーのタスク枯渇時に即座に `SYS_futex` (wait) システムコールを発行すると、カーネル空間へのコンテキストスイッチと復帰遅延（数 μs）が発生し、後続タスク到着時の起床ジッター要因となっていた。
また、従来の `%scheduler-idle-backoff!` は Scheme の空ループであったため、x86-64 `PAUSE` 命令 (`rep nop`) が発行されず、SMT パイプラインの浪費を招いていた。
本 Issue では、アセンブリ低レベル PAUSE ループプリミティブ（`%sys-cpu-pause`）を導入し、`SYS_futex` に突入する前に有界な適応的スピン（Adaptive Spinning）フェーズ（`futex-park-adaptive!`）を設けることで、短時間で連続到着するタスクのシステムコール発行ゼロでの即時ディスパッチを実現した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 7.4.2 & Section 14.9 Task 7.2)
- 関連評価書: [Synapse Concurrency Benchmark Suite](../../benchmarks/concurrency_evaluation.md)
- 先行 Issue: [Issue #676: Linux SYS_futex park/unpark](676-implement-synapse-futex-park-unpark-primitives.md)
- 先行 Issue: [Issue #675: Linux ネイティブスレッド生成](675-implement-synapse-native-multithread-worker-pool.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/futex.s](../../../ulisp/runtime/concurrency/futex.s) (PAUSE 命令ループプリミティブ `ulisp_fn__pctsys_cpu_pause`)
- [x] [ulisp/runtime/concurrency/futex.scm](../../../ulisp/runtime/concurrency/futex.scm) (`futex-spin-pause!`, `futex-park-adaptive!`, 有界スピン上限・3-State CAS セマンティクス保護)
- [x] [ulisp/lib/ulisp/concurrency/futex.sld](../../../ulisp/lib/ulisp/concurrency/futex.sld) (R7RS エクスポートシンボル追加)
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../../ulisp/runtime/concurrency/scheduler.scm) (`%scheduler-idle-backoff!` の PAUSE 最適化およびワーカー待機ループへの適応的スピン統合)
- [x] [tests/concurrency/test_futex.scm](../../../tests/concurrency/test_futex.scm) (適応的スピン動作検証・バイパス検証・CWE 境界テスト: 47/47 PASS)
- [x] [tests/concurrency/test_scheduler.scm](../../../tests/concurrency/test_scheduler.scm) (118/118 PASS)
- [x] [tests/concurrency/test_multithread_scheduler.scm](../../../tests/concurrency/test_multithread_scheduler.scm) (23/23 PASS)

---

## 4. 実装方針と成果 / Implementation & Results
Target Branch: `feat/679-synapse-adaptive-spinning-futex-reduction`

1. **アセンブリ PAUSE 命令ループプリミティブの実装 (`futex.s`)**:
   - `ulisp_fn__pctsys_cpu_pause(cycles)`:
     - x86-64 `pause` 命令 (`0xF3 0x90` / `rep nop`) を指定回数実行するアセンブリハンドラを実装。
     - CPU パイプラインストールを解消し、同一物理コアの SMT スレッドに実行リソースを譲歩。
2. **適応的スピン待機 API の実装 (`futex.scm`)**:
   - `(futex-spin-pause! [cycles])`: セーフラッパーおよび引数型検査。
   - `(futex-park-adaptive! cell [max-spins] [timeout-ms])`:
     - 有界スピン（デフォルト 256 回、上限 4096 回、CWE-400 対策）。
     - スピンループ内で `NOTIFIED` (2) トークンを CAS (2 ➔ 0) で監視し、到着時はシステムコールを発行せず即座に `#t` でバイパス復帰。
     - スピン上限超過時のみ `SYS_futex`（`futex-park!`）を呼んで省電力休止。
3. **スケジューラ待機ループへの適応的スピン統合 (`scheduler.scm`)**:
   - `%scheduler-idle-backoff!` を空ループから `(%sys-cpu-pause 16)` へ最適化。
   - `%scheduler-worker-native-loop` において、タスク枯渇時に `futex-park-adaptive!` を呼び出し、短時間でタスクが再投入された際のカーネルコンテキストスイッチをゼロ化。
4. **セキュリティ・例外設計 (CWE Guards)**:
   - **CWE-400 (Resource Exhaustion)**: `max-spins` を最大 4096 回に厳格クランプ。
   - **CWE-833 (Deadlock / Lost Wakeup)**: 3-State CAS（EMPTY=0, PARKED=1, NOTIFIED=2）との整合性を維持。
   - **CWE-843 (Type Confusion)**: 型アサーションの実装。

---

## 5. 完了条件 (Definition of Done: DoD) 検証結果
- [x] `futex.s` に `ulisp_fn__pctsys_cpu_pause` が実装され、GNU ld スタック警告なくリンク可能であること。 ➔ **PASS**
- [x] `futex.scm` に `futex-spin-pause!` および `futex-park-adaptive!` が実装されていること。 ➔ **PASS**
- [x] `scheduler.scm` の `%scheduler-idle-backoff!` およびワーカー待機ループが適応的スピンに対応していること。 ➔ **PASS**
- [x] `test_futex.scm` に適応的スピン（トークン即時バイパス、有界スピン上限、型境界）のテストケースが追加され、全件 PASS すること。 ➔ **PASS (47/47 PASS)**
- [x] 既存の並行テストスイート（`test_futex`, `test_scheduler`, `test_multithread_scheduler`, `test_concurrency_harness`）が 100% PASS すること。 ➔ **PASS (100/100 harness iterations, 13,100 assertions PASS)**
- [x] S式構文バランス検査（`lint_sexpr`）、Python 静的解析が 100% PASS すること。 ➔ **PASS**
- [x] 絶対パスリンクが 0 件であり、全内部リンクが相対パスであること。 ➔ **PASS (0 件検出)**

