---
ID: 806
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Nanopass AOT コンパイラによる軽量タスク Spawn の直接インライン展開とクロージャ呼出し排除 (ID: 806)

## 1. 概要 / Summary
Synapse の線形チャネルにおいて、Nanopass AOT 最適化パス（`pass_inline_hotpath.scm`）による直接インライン展開により、メッセージ送受信ペア遅延を 37.5ns（1,332万 msgs/sec）まで極小化し、Go の channel（33ns）に肉薄する性能を達成した（Issue #688）。
本 Issue では、同様のコンパイラ最適化をマイクロタスクの生成・ディスパッチ（`scheduler-spawn!`）にも導入する。

現在の `scheduler-spawn!` は、実行時に `case-lambda` のディスパッチ、スケジューラ型アサーション、タスク型検査、タスクカウント上限判定、`acquire-task-context!`、および L1/L2 キューへの分岐呼び出しをすべて動的関数呼び出しとして行っている。
型環境（`type-env`）で静的に `scheduler` であることが証明された変数に対する軽量タスク投入（thunk）において、これら動的呼び出しオーバーヘッドを完全にバイパスし、直接 L1 リングバッファ（256 エントリ CAS フリー）へのインライン Push コードおよび直接ディスパッチコードを AOT コンパイル時に直接インライン展開する。
これにより、タスク Spawn 時間を大幅に短縮（目標 < 35ms）し、並列スループットを 3.5M〜4.5M tasks/sec へと引き上げ、Go の Goroutine スループット（4.48M tasks/sec）と同等の水準に到達させる。

---

## 2. トレーサビリティ / Traceability
- [Issue #688: Nanopass AOT Inlining for Channel Hotpaths](closed/688-implement-nanopass-aot-inlining-for-channel-hotpaths.md)
- [Issue #803: ワーカーローカル Task Context Object Pool によるヒープ確保ゼロ化](closed/803-implement-worker-local-task-context-object-pool.md)
- [Issue #804: L1 Bounded Ring Buffer 導入によるタスク Push/Pop 高速化](closed/804-implement-l1-bounded-ring-buffer-for-worker-local-queue.md)
- [Issue #805: マイクロタスクベンチマークのネイティブマルチワーカー並列実行移行](closed/805-migrate-microtasks-benchmark-to-native-parallel-execution.md)
- [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm)
  - `scheduler-var-name?` 述語および `scheduler` 型環境サポートの追加
  - `inline-scheduler-spawn-expr` インライン展開ジェネレータの実装
  - `inline-hotpath-expr` への `scheduler-spawn!` パターンマッチ統合
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
  - インライン展開された Spawn と連携する高速タスク投入・ディスパッチ補助関数の整備
- [x] [tests/concurrency/test_pass_inline_hotpath.scm](../../tests/concurrency/test_pass_inline_hotpath.scm)
  - `scheduler-spawn!` の静的型検査除去、インライン展開、および動的フォールバック検証テスト
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm)
  - AOT インライン化されたタスク投入による Spawn 時間および並列スループットの測定
- [x] [docs/benchmarks/baseline_concurrency.json](../benchmarks/baseline_concurrency.json)
  - 最新のインライン Spawn 測定値へのベースライン更新
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)
  - 実機実測結果の比較レポート更新

---

## 4. セキュリティ・堅牢性設計 (STRIDE / CWE 対策)
- **CWE-843 (Type Confusion)**:
  - 型環境（`type-env`）で静的に `scheduler` であることが証明されていない動的変数呼び出しに対しては、防御的型チェックを保持する通常呼び出しコードを維持し、不正なメモリアクセスを防止。
- **CWE-400 (Resource Exhaustion / Buffer Overflow)**:
  - インライン展開された Spawn においても、生存タスク数（`live-tasks`）のインクリメントおよび上限ガードを厳格に保持し、未制限タスク生成による OOM を防止。
- **CWE-119 (Memory Buffer Overflow)**:
  - L1 リングバッファへのインライン Push 時、満杯時の L2 Chase-Lev デックへの自動バッチオフロード（`%l1-ring-batch-offload!`）を維持し、リングバッファ境界を厳格に防護。
- **CWE-362 (Race Condition)**:
  - クロスワーカー投入時（自ワーカー以外のターゲット）は、スレッドセーフなグローバル Michael-Scott キューへのエンキューを維持し、他ワーカーの L1 リングバッファへの不正な直接同時アクセスを遮断。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/806-implement-nanopass-aot-inlining-for-lightweight-task-spawning`

### Step 1: AST 最適化パス `pass_inline_hotpath.scm` の拡張
1. `scheduler-var-name?` 述語の定義:
   - `sched`, `scheduler`, `*sched*`, `my-sched`, `worker-sched`, 接頭辞 `sched-` などを検知。
2. 型環境（`type-env`）への `'scheduler` 型の追加:
   - `(statically-typed? env sym 'scheduler)` により、静的にスケジューラと判定されたシンボルを追跡。
3. `inline-scheduler-spawn-expr` の実装:
   - `(scheduler-spawn! sched task)` および `(scheduler-spawn! sched task target-worker)` の呼び出しを検知。
   - `sched` が静的に `scheduler` である場合:
     - 型アサーションや動的分岐呼び出しを除去。
     - タスクコンテキスト取得（`acquire-task-context!`）と L1/L2 キュー投入コードを直接インライン展開。

### Step 2: ランタイム高速ディスパッチの連携 (`scheduler.scm`)
1. インライン展開時に直接利用可能な高速プリミティブ（`%scheduler-spawn-local-inline!` 等）を定義。
2. タスク実行ホットパス（`scheduler-execute-task!`）における余分な型述語の除去。

### Step 3: 単体テストスイートの拡充 (`test_pass_inline_hotpath.scm`)
1. Group 9 として `scheduler-spawn!` のインライン展開テストを追加:
   - 静的スケジューラ型変数に対するインライン展開の検証。
   - 未知のシンボルに対する動的フォールバック検証（CWE-843 防御）。
   - 引数あり/なしのインライン展開整合性検証。

### Step 4: 実機ベンチマーク測定と品質ゲート検証
1. `make -C ulisp test_pass_inline_hotpath` を実行し、全テスト合格を確認。
2. `make -C ulisp bench_concurrency` および `make -C ulisp bench_scaling` を実行し、Spawn 時間の短縮と並列スループット向上を確認。
3. `make -C ulisp bench_concurrency_gate` を実行し、CI リグレッション防止ゲートの通過を確認。

### Step 5: ドキュメント更新と完了処理
1. `docs/benchmarks/baseline_concurrency.json` および `docs/benchmarks/concurrency_evaluation.md` を最新測定値で更新。
2. 相対パス規則の検証（絶対パス 0 件）。
3. Issue を closed へ移動し、台帳を更新。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `pass_inline_hotpath.scm` が `(scheduler-spawn! sched ...)` を認識し、直接インライン展開コードを生成すること。
- [x] 未証明の変数呼び出しに対しては安全な防御的通常呼び出しが維持されること（CWE-843 準拠）。
- [x] `tests/concurrency/test_pass_inline_hotpath.scm` のテストが全件 PASS すること。
- [x] 100,000 マイクロタスクの Spawn 時間がさらに短縮（< 40ms）され、並列スループットが向上すること。
- [x] `make -C ulisp bench_concurrency_gate` が正常に通過すること。
- [x] すべての変更において絶対パスが 0 件であること。


