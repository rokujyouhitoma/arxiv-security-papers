---
ID: 675
種別: Feature
優先度: High
ステータス: Closed (Resolved)
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
  - [Issue #671 (コルーチン ID アトミック化)](closed/671-fix-synapse-coroutine-id-atomic-allocation.md)
  - [Issue #672 (Epoch 原子的進行保証)](closed/672-fix-synapse-epoch-advance-atomic-return-race.md)
  - [Issue #673 (グローバルアトミック Task ID 採番器)](closed/673-implement-synapse-global-atomic-task-id-allocator.md)
  - [Issue #674 (スケジューラ統計カウンタのアトミック化)](closed/674-fix-synapse-scheduler-stats-atomic-counters.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/thread.s](../../ulisp/runtime/concurrency/thread.s)
- [ ] [ulisp/runtime/concurrency/thread.scm](../../ulisp/runtime/concurrency/thread.scm)
- [ ] [ulisp/lib/ulisp/concurrency/thread.sld](../../ulisp/lib/ulisp/concurrency/thread.sld)
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [ulisp/lib/ulisp/concurrency/scheduler.sld](../../ulisp/lib/ulisp/concurrency/scheduler.sld)
- [ ] [ulisp/Makefile](../../ulisp/Makefile)
- [ ] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm)
- [ ] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)

---

## 4. 根本原因分析 (RCA) & セキュリティ脅威分析
1. **構造的ボトルネック**:
   `scheduler.scm` の `%scheduler-step-all!` は単一の OS スレッドで再帰呼び出しを行い、全ワーカーを順次実行している。ロックフリーデータ構造（Chase-Lev Deque や Michael-Scott Queue）はマルチコア対応済みであるにもかかわらず、OS スレッドが 1 つしかないため、物理コアが 8〜64 コア存在しても 1 コアしか稼働せず、並列計算プレーン（Layer 2）の潜在性能を殺している。

2. **セキュリティ脅威分析 (STRIDE / CWE)**:
   - **CWE-119 / CWE-787 (Buffer / Stack Overflow)**:
     新規生成された子スレッドのスタック領域が浅く設定された場合、多段再帰や大量の局所変数確保によって隣接メモリを破壊するリスク。
     → **Mitigation**: 各スレッドに十分な 1MB スタックを `mmap` で確保し、最下部 4KB ページに `mprotect(PROT_NONE)` によるガードページを配置してオーバーフローを即時 SIGSEGV として補足。
   - **CWE-362 (Race Condition / Data Race)**:
     複数の OS ネイティブスレッドが同一スケジューラインスタンス内のデータ構造を並行操作する際の競合。
     → **Mitigation**: 統計カウンタおよびタスク ID 採番器は既に `<atomic-box>`（#673, #674）で完全保護。Deque 操作は Chase-Lev アルゴリズム（LIFO 所有者 / FIFO 盗取者アトミック CAS）を厳格遵守。
   - **CWE-401 (Improper Release of Memory Before Removing Last Reference / Resource Leak)**:
     スレッド終了時にスレッドスタックやスレッドディスクリプタが解放されず累積リーク（ゾンビスレッド）するリスク。
     → **Mitigation**: スレッドプールのライフサイクル管理（`scheduler-stop-native-workers!`）において、全スレッドの終了を同期検知し、スタックメモリを決定論的に `munmap` 解放。
   - **CWE-843 (Type Confusion)**:
     低レベルなスレッド起動プリミティブに不正なメモリアドレスや非手続きオブジェクトが渡されるリスク。
     → **Mitigation**: Scheme 側のラッパーにおいて引数の型検査（手続き述語、整数境界チェック）を厳格に実施。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 単一 OS スレッド上の時分割ステップ実行ループ（現状）を継続利用する。
* **恒久対策 (Permanent Fix)**:
  1. Linux AMD64 ネイティブの `sys_clone` システムコールラッパーをアセンブリ（`thread.s`）で実装。
  2. `sched_setaffinity` により、Worker $i$ を CPU Core $i$ に 1:1 バインド。
  3. 各ワーカーが独立した常駐ループ（`%scheduler-worker-native-loop`）を各 OS スレッドで実行するマルチスレッドワーカープールを構築。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/675-native-multithread-worker-pool`

### Step 1: ネイティブスレッドアセンブララッパー (`ulisp/runtime/concurrency/thread.s`)
1. AMD64 Linux システムコール 56 (`SYS_clone`):
   - フラグ: `CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM` (0x00050f00)。
   - スタック確保: `SYS_mmap` (syscall 9) により 1MB スタック + ガードページを動的確保。
   - 子スレッド起動トランポリン: スタックトップをアライメント調整後、指定された Scheme 実行関数を呼び出し、完了時は `SYS_exit` (syscall 60) を呼ぶ。
2. CPU アフィニティシステムコール 203 (`SYS_sched_setaffinity`):
   - `core_id` を受け取り、対応するビットマスクを設定して自スレッド（tid = 0）の CPU アフィニティを固定。
3. CPU コア数取得:
   - `/sys/devices/system/cpu/online` または Linux `SYS_sched_getaffinity` によるオンラインコア数の取得。

### Step 2: Scheme 低レベルスレッドライブラリ (`thread.scm`, `thread.sld`)
1. アセンブリルーチンへの Scheme 境界インターフェース:
   - `(%sys-spawn-thread fn-ptr arg-ptr stack-size)`
   - `(%sys-set-affinity core-id)`
   - `(%sys-online-cpu-count)`
2. R7RS ライブラリ `(ulisp concurrency thread)` の定義とエクスポート。

### Step 3: スケジューラマルチスレッド統合 (`scheduler.scm`)
1. ワーカー独立実行ループ:
   ```scheme
   (define (%scheduler-worker-native-loop sched worker-id)
     (let loop ()
       (if (scheduler-running? sched)
           (begin
             (scheduler-worker-step! sched worker-id)
             (loop))
           #t)))
   ```
2. スレッドプール起動・停止管理:
   - `(scheduler-start-native-workers! sched)`: 各ワーカー（0〜N-1）を独立スレッドとして spawn。
   - `(scheduler-stop-native-workers! sched)`: 全スレッドへ停止シグナル（`atomic-set!`）を送り合流（Join）。

### Step 4: ビルドシステム統合 (`ulisp/Makefile`)
1. `runtime/concurrency/thread.s` を `build/thread.o` としてコンパイル。
2. スケジューラテストおよびハーネスのリンク依存関係に `build/thread.o` を追加。

### Step 5: テストスイート拡充
1. `tests/concurrency/test_multithread_scheduler.scm`:
   - 複数物理コア上での並列タスク実行（100,000 タスク）におけるスループット測定と全タスク完遂検証。
   - 各スレッドの CPU アフィニティが期待通り設定されているかの検証。
2. `tests/concurrency/concurrency_harness.scm`:
   - ネイティブマルチスレッド環境下でのカオスジッター並行競合テスト。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `thread.s` により `sys_clone` を介して子スレッドが正常に起動・実行・終了できること。
- [x] `sched_setaffinity` によりワーカーが特定の CPU コアに固定され、コアマイグレーションが発生しないこと。
- [x] 複数ネイティブスレッド並列実行下でマイクロタスクが破損・脱落なく 100% 完了すること。
- [x] 終了時にゾンビスレッドや未回収スタックメモリが残らないこと。
- [x] `make -C ulisp test_multithread_scheduler` (23 passed), `test_scheduler` (118 passed), `test_concurrency_harness` (100 反復 13,100 アサーション) が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。

