---
ID: 681
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] NUMA-Aware 階層型 Work-Stealing スケジューリングの実装 (ID: 681)

## 1. 概要 / Summary
現在の Synapse Work-Stealing スケジューラ（[scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)）は、ワーカーのローカルデックおよびグローバルキューが枯渇した際、全ワーカーから一様にランダムスチール（Victim Selection）を行っている。
しかし、物理マルチコアやマルチソケット環境（NUMA: Non-Uniform Memory Access, AMD EPYC / Intel Xeon / マルチCCD構成）においては、別ソケットや別 NUMA ノード上のデックからタスクをスチールすると、QPI/UPI/Infinity Fabric 等の相互接続バスを経由した高遅延メモリアクセス（100〜300 ns vs ローカル 30〜50 ns）が発生し、L3 キャッシュのヒット率が著しく低下する。

本 Issue では、各ワーカーの NUMA ノード / L3 キャッシュドメインを認識し、同一 NUMA ノード内のワーカーから優先的にタスクをスチールし、ローカルドメインが完全に枯渇した場合にのみリモートノードからスチールを行う **2階層型 Work-Stealing（Hierarchical / 2-Tier Work Stealing）** アルゴリズムを設計・実装する。これにより、L3 キャッシュ局所性を最大化しながら、不均一な負荷状況下での CPU 遊休を防止し、大規模並行環境におけるスループットと決定論的低遅延を飛躍的に向上させる。

---

## 2. トレーサビリティ / Traceability
- **設計仕様書**: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Section 7.1, 7.2, 7.4)
- **関連ベンチマーク**: [Synapse Concurrency Benchmark Suite](../benchmarks/concurrency_evaluation.md)
- **先行 Issue**:
  - [Issue #635: M:N Work-Stealing スケジューラの実装](635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #675: ネイティブスレッド生成と CPU コアピニング](675-implement-synapse-native-multithread-worker-pool.md)
  - [Issue #680: 線形チャネルの 64 バイト・キャッシュラインパディングと Unboxed Fast-Path](680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/thread.s](../../ulisp/runtime/concurrency/thread.s): Linux `SYS_getcpu` (syscall 309) を用いた CPU コア ID および NUMA ノード ID のネイティブ取得ルーチン (`ulisp_fn__pctsys_getcpu_core`, `ulisp_fn__pctsys_getcpu_node`)
- [x] [ulisp/runtime/concurrency/thread.scm](../../ulisp/runtime/concurrency/thread.scm): `%sys-getcpu-core`, `%sys-getcpu-node` スタブおよび高レベル API `(get-current-cpu-node)`, `(get-current-core-id)`, `(get-current-node-id)` の提供
- [x] [ulisp/lib/ulisp/concurrency/thread.sld](../../ulisp/lib/ulisp/concurrency/thread.sld): `get-current-cpu-node`, `get-current-core-id`, `get-current-node-id` のエクスポート
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm):
  - `<worker-context>` への `node-id` (NUMA ノード) フィールド追加およびアクセサ `worker-node-id`
  - `<work-stealing-scheduler>` への `node-count` (NUMA ノード総数) およびノード毎ワーカーグループ配列表（`%build-node-workers-table`, `scheduler-node-workers`）の保持
  - コンストラクタ `make-work-stealing-scheduler` の `node-count` 引数サポート（`case-lambda` 拡張）
  - 2階層型スチールアルゴリズム `%scheduler-try-steal!` (Tier 1: `%tier1-steal-loop` 同一ノード内優先スチール、Tier 2: `%tier2-steal-loop` リモートノードフォールバック)
  - ワーカー統計情報（`stats`）へのローカルスチール・リモートスチール成功/試行回数カウンタ（8スロット）の追加
  - `scheduler-stats` への `node-count`, `node-id`, `local-steals-*`, `remote-steals-*` テレメトリの追加
- [x] [ulisp/lib/ulisp/concurrency/scheduler.sld](../../ulisp/lib/ulisp/concurrency/scheduler.sld): 新規アクセサ・手続きのエクスポート
- [x] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm): Group 7（SYS_getcpu 疎通、NUMA トポロジ初期化、Tier 1 ローカル優先スチール検証、Tier 2 リモートフォールバックスチール検証、CWE 防御）のテスト追加
- [x] [tests/concurrency/test_multithread_scheduler.scm](../../tests/concurrency/test_multithread_scheduler.scm): Group 7（マルチスレッド並行実行下での 2 ノード NUMA 階層スチール整合性テスト）の追加
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm): マルチワーカー実行時のスケジューリングスループット測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/681-synapse-numa-aware-hierarchical-work-stealing`

### Step 1: Linux `SYS_getcpu` によるハードウェアトポロジ検出 (`thread.s`, `thread.scm`)
1. `thread.s` に Linux x86-64 `syscall 309` (`SYS_getcpu`) を実装:
   - スタック上のローカルバッファに `cpu` と `node` を取得し、即座に Scheme fixnum（`shl rax, 2`）にエンコードして返却。
2. `thread.scm` に `(get-current-cpu-node)` を定義し、システムコール失敗時または非 Linux 環境では `(cons 0 0)` を安全にフォールバック返却。

### Step 2: `<worker-context>` および `<work-stealing-scheduler>` のトポロジ拡張 (`scheduler.scm`)
1. `<worker-context>` に `node-id` フィールドを追加:
   - `worker-node-id`: ワーカーが所属する NUMA ノード番号（`0 .. node-count - 1`）。
   - ワーカーの統計情報ベクタ `stats` を拡張（8要素）:
     - `[0]`: 実行タスク数
     - `[1]`: 総スチール試行数
     - `[2]`: 総スチール成功数
     - `[3]`: イールド数
     - `[4]`: ローカル (Intra-Node) スチール試行数
     - `[5]`: ローカル (Intra-Node) スチール成功数
     - `[6]`: リモート (Inter-Node) スチール試行数
     - `[7]`: リモート (Inter-Node) スチール成功数
2. `<work-stealing-scheduler>` に `node-count` および `node-workers` (ノードごとのワーカー ID ベクタ配列) を追加:
   - `(scheduler-node-count sched)`: NUMA ノード数。
   - `(scheduler-node-workers sched node-id)`: 指定ノードに属するワーカー ID のベクタ。
   - コンストラクタ `make-work-stealing-scheduler`:
     - `(make-work-stealing-scheduler [worker-count] [initial-deque-cap] [node-count])`
     - `node-count` 省略時は `1`。

### Step 3: 2階層型 Work-Stealing アルゴリズムの実装 (`%scheduler-try-steal!`)
1. **Tier 1: 同一 NUMA ノード内スチール (Intra-Node Steal)**:
   - ワーカー $W$（所属ノード $N$）のローカルデックおよびグローバルキューが空になった場合:
   - ノード $N$ に属する他のワーカー群からランダムに被害者（Victim）を選定。
   - 最大 $2 \times (\text{local-workers} - 1)$ 回試行。
   - 成功した場合、タスクを実行し、`local-steals-succeeded` をインクリメント。
2. **Tier 2: リモート NUMA ノードスチール (Inter-Node Fallback Steal)**:
   - Tier 1 の試行がすべて失敗し、ローカルノードが完全に枯渇している場合のみ発動。
   - $N$ 以外のリモートノードからランダムに被害ノードを選び、そのワーカーからスチール。
   - 最大 $2 \times \text{remote-workers}$ 回試行。
   - 成功した場合、タスクを実行し、`remote-steals-succeeded` をインクリメント。
   - 失敗した場合はアイドルバックオフ（`%sys-cpu-pause` / Futex Park）へ移行。

### Step 4: セキュリティ・ロバストネス設計 (CWE 防止)
- **CWE-843 (Type Confusion)**: `node-count` および `node-id` の厳格な整数型アサーション。
- **CWE-400 (Resource Exhaustion)**: `node-count` は `[1 .. worker-count]` の範囲にクランプ。スチールループの最大反復上限（`2 * num-workers`）の徹底により無限ループ・デッドロックを防止。
- **CWE-362 (Race Condition)**: 階層スチール時も Chase-Lev 既定の CAS（`deque-steal!`）を使用し、競合発生時の整合性を 100% 担保。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `thread.s` / `thread.scm` に `get-current-cpu-node` が実装され、CPU/NUMA ノード情報が取得可能であること。
- [x] `<worker-context>` に `worker-node-id` が保持され、ワーカーが所属 NUMA ノードを認識できること。
- [x] `<work-stealing-scheduler>` が `node-count` およびノード別ワーカーグループを管理できること。
- [x] 2階層スチールアルゴリズムにより、同一ノードワーカーからのスチールが優先実行され、枯渇時のみリモートスチールが行われること。
- [x] 統計情報（`scheduler-stats`）にローカル/リモートスチールの成功・試行回数が記録・確認できること。
- [x] `tests/concurrency/test_scheduler.scm` および `tests/concurrency/test_multithread_scheduler.scm` に NUMA 階層スチールのテストケースが追加され、100% PASS すること。
- [x] 既存の並行テストスイート（`test_channel`, `test_atomic`, `test_queue`, `test_concurrency_harness`）が 100% PASS すること。
- [x] S式構文バランス検査（`lint_sexpr`）、Python 静的解析（`mypy --strict src`）が 100% PASS すること。
- [x] ドキュメント内の全内部リンクが相対パスであり、絶対パス（`file:///` 等）が 0 件であること。

---

## 6. 検証結果サマリー / Verification Results Summary
- **Unit & Integration Tests**:
  - `test_scheduler.scm`: 150 passed, 0 failed (Group 7 NUMA 2-Tier Stealing 100% PASS)
  - `test_multithread_scheduler.scm`: 29 passed, 0 failed (Group 7 NUMA Parallel Multi-Worker 100% PASS)
  - `test_channel.scm`: 221 passed, 0 failed
  - `test_queue.scm`: 102 passed, 0 failed
  - `test_atomic.scm`: 50 passed, 0 failed
  - `test_concurrency_harness.scm`: 100 iterations, 13,100 assertions, 0 failed
- **Microtasks Benchmark**:
  - `bench_microtasks.scm`: 3,134,618 tasks/sec (319 ns/task, 100,000 tasks deterministic completion)
- **Quality Gates**:
  - `lint_sexpr`: 154 files balanced
  - `mypy --strict src`: 617 source files passed with zero issues
  - Relative links: 0 absolute path references


