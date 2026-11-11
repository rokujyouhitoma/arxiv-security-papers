---
ID: 803
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ワーカーローカル Task Context Object Pool によるヒープ確保ゼロ化と Spawn 高速化 (ID: 803)

## 1. 概要 / Summary
Synapse 並行処理基盤におけるマイクロタスク生成性能（現在 1.56M tasks/sec、Spawn 時間 40ms）を劇的に向上させ、Go の Goroutine（4.07M tasks/sec）を凌駕するため、タスクコンテキスト（`<task-context>`）生成時におけるホストヒープ割り当て（`make-vector`）を完全撤廃する。

Go ランタイムでは、各 P（Processor）がスレッドローカルな Free List キャッシュ（`runtime.gfget` / `gfput`）を保持しており、終了した goroutine の `g` 構造体を破棄せず O(1) で即時再利用することで、100,000 タスク生成時のヒープ割り当て回数を実質ゼロ（0 bytes）に抑えている。
一方、現在の Synapse では Issue #800 により稀少メタデータの遅延割り当て化（91% 削減）を実現したものの、タスク生成（`scheduler-spawn!`）のたびに依然としてホストヒープから 17 スロットの `<task-context>` ベクタを新規確保している。

本 Issue では、各ワーカー（またはスケジューラ）に終了済みタスクコンテキストをキャッシュする固定長配列の **Task Context Object Pool (Free List)** を導入する。タスク Spawn 時はプールから O(1) でコンテキストを取得してフィールドを再利用し、タスク終了時は即座にプールへ返却する。これにより 100,000 タスク生成時のヒープ割り当てをゼロ化し、L1/L2 キャッシュ局所性を極限まで高めて Spawn 時間を 40ms から 10ms 以下へ大幅短縮する。

---

## 2. 専門家レビュー視点 (Multi-Agent Perspectives)

- **Project Manager (PM)**:
  - Go の Goroutine 性能超越（4.07M tasks/sec 突破）に向けた最重要マイルストーンである。全テスト（単体・並行・ベンチマーク）の 100% PASS を前提に、Spawn 遅延とヒープアロケーションの劇的削減を達成する。
- **Systems Architect**:
  - 各ワーカーの TLS スロット（`%asm-current-worker-slot`）またはスケジューラに固定長配列（有界リングスタック、512 エントリ）を配備し、メモリフラグメンテーションと無制限のプール肥大化を防止する（CWE-400 対策）。
- **Software Development (SWD)**:
  - `acquire-task-context!` および `release-task-context!` を新設し、`channel.scm`、`scheduler.scm`、`links.scm` のホットパスにシームレスに結合する。再利用時のフィールドリセット（TID 昇格、reductions 初期化、残存アリーナオフセットのリセット）を漏れなく実装する。
- **Information Security Specialist**:
  - CWE-416 (Use-After-Free: 返却済みタスクの二重参照・改ざん) および CWE-362 (並行アクセス競合) を徹底防止する。タスクテーブル登録解除後かつ `'terminated` シール後にのみ返却を許可し、プール内コンテキストの状態を `'pooled` に固定して不正な再実行を即時拒絶する。
- **Software Quality Assurance Specialist (SQA)**:
  - 100,000 タスク生成・実行時におけるプールヒット率（再利用率 > 95%）と Spawn 時間短縮（40ms -> < 15ms）をベンチマークで定量実証し、10 回連続の並行ストレステストを 0 failures で通過させる。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/channel.scm](../../ulisp/runtime/concurrency/channel.scm) - Task Context プール管理・リセット・再利用プリミティブ（`acquire-task-context!`, `release-task-context!`, `%reset-task-context!`）の実装
- [x] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - `scheduler-spawn!` および `%normalize-task-context` におけるプールからの取得結合
- [x] [ulisp/runtime/concurrency/links.scm](../../ulisp/runtime/concurrency/links.scm) - `%task-fast-normal-termination!` および `task-handle-termination!` におけるプールへの返却結合
- [x] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm) - オブジェクトプール動作・リサイクル整合性テスト（Group 18）の追加
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - Spawn レイテンシ・アロケーション削減効果の測定
- [x] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - Go との比較ベンチマーク評価レポートの更新

---

## 4. セキュリティ分析と防御策 (Threat Modeling & CWE)
1. **CWE-416: Use-After-Free (返却済みタスクコンテキストの不正再利用・破壊)**:
   - 脅威: タスク終了後に別スレッドが古いタスク参照を保持していた場合、プールから再割り当てされた別タスクのコンテキストを破壊する危険。
   - 防御策:
     - プールへの返却は、必ず `task-table-unregister!` によってグローバルタスクテーブルから安全に登録解除された後にのみ行う。
     - 返却時にタスク状態を `'pooled` にシール。万一古い参照から `scheduler-execute-task!` 等が呼ばれた場合、即座に `#f` またはエラーを返し実行をブロック。
     - コンテキストの `next-run`、`blocked-on`、`handler-chain`、`escape-k` を完全にクリアし、過去の実行状態が後続タスクにリークすることを防ぐ。
2. **CWE-362: Race Condition (プール操作における並行データ競合)**:
   - 脅威: 複数ワーカーが同一のプールスロットから同時にタスクを取り出し、同一コンテキストが二重割り当てされる危険。
   - 防御策:
     - ワーカーローカルスロットごとに独立したプール（配列）を割り当て、自ワーカーの Push/Pop はロックフリー（CAS なし）で完結させる。
     - ワーカー未特定時（メインスレッド等）はアトミック CAS 付きグローバルフリーリストを使用。
3. **CWE-400: Uncontrolled Resource Consumption (プールの無制限肥大化)**:
   - 脅威: 短時間に大量のタスクが返却された際にプール配列が肥大化しメモリを圧迫する危険。
   - 防御策:
     - 各ワーカープールの容量を固定長（例: 512 エントリ）に制限。プール満杯時の返却オブジェクトはプールに積まず、通常通りホスト GC の自動回収に委ねる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/803-implement-worker-local-task-context-object-pool`

### Step 1: Task Context Pool 構造およびリセットプリミティブの実装 (`ulisp/runtime/concurrency/channel.scm`)
1. プール容量定数 `*task-context-pool-capacity*`（デフォルト 512）を定義。
2. ワーカーローカルプールベクタ `*task-context-pools*`（ワーカー数分の固定長ベクタ配列）およびスタックトップインデックス `*task-context-pool-tops*` を配備。
3. `%reset-task-context!(ctx, tid, state, reductions, epoch)`:
   - 既存の `<task-context>` ベクタのスロットをインプレースで初期化。
   - `meta-box` は既存のアトミックボックスを保持したまま `(atomic-set! (task-meta-box ctx) #f)` でリセット（ヒープ確保ゼロ）。
4. `%acquire-task-context!(wid, tid)`:
   - ワーカー `wid` のプールから O(1) で pop。
   - プールが空の場合は従来の `%create-task-context-default` で新規確保。
5. `%release-task-context!(ctx, wid)`:
   - 状態を `'pooled` にシールし、ワーカー `wid` のプールに push。
   - プール満杯時は何もしない（GC に回収させる）。

### Step 2: `scheduler-spawn!` へのオブジェクトプール結合 (`ulisp/runtime/concurrency/scheduler.scm`)
1. `%normalize-task-context` において、`procedure?` や `coroutine-context?` のタスクに対し、無条件の `make-task-context` ではなく `%acquire-task-context!` を呼び出してコンテキストを再利用。
2. タスクテーブルへの登録（`%register-task-in-table!`）を O(1) で実行。

### Step 3: タスク終了パスにおけるプール返却の結合 (`ulisp/runtime/concurrency/links.scm`)
1. `%task-fast-normal-termination!`（正常終了 Fast-Path）において、タスクテーブルからの登録解除直後に `%release-task-context!` を呼び出す。
2. `task-handle-termination!`（Slow-Path）の末尾でも同様に返却。

### Step 4: 単体テスト・回帰テストの整備 (`tests/concurrency/test_scheduler.scm`)
1. Group 18（Task Context Object Pool & Recycling Verification）を追加：
   - プールからの取得と再利用の O(1) 動作検証。
   - 再利用時の TID 昇格および残存状態クリーンアップ検証。
   - 返却済みタスク（`'pooled`）の実行拒絶（CWE-416 防御）検証。
   - 10,000 タスク反復 spawn 時のヒープ割り当て削減・キャッシュヒット検証。

### Step 5: ベンチマーク測定 & CI 性能ゲート検証
1. `benchmarks/concurrency/bench_microtasks.scm` を実行し、Spawn 時間およびスループットの大幅向上を確認。
2. `make test_concurrency_stress`（10回連続並行ストレステスト）を通過。
3. `make -C ulisp bench_concurrency_gate` を通過。
4. `docs/benchmarks/concurrency_evaluation.md` を更新。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 各ワーカーに Task Context Pool が導入され、コンテキスト再利用（acquire/release）が O(1) で動作すること。
- [ ] 再利用時に TID、状態、reductions、アリーナオフセット、エスケープ継続が完全にリセットされること。
- [ ] プール内タスクに対する不正アクセスが遮断されること（CWE-416 防御）。
- [ ] 100,000 マイクロタスクの Spawn 時間が 40ms から大幅短縮（目標 < 15ms）されること。
- [ ] 既存の並行性テストスイート（`test_scheduler`, `test_channel`, `test_links_monitors`, `test_supervisor`, `test_multithread_scheduler`）が全件 PASS すること。
- [ ] `make test_concurrency_stress`（10回連続並行ストレステスト）が 0 failures で通過すること。
- [ ] `make -C ulisp bench_concurrency_gate` をクリアすること。
- [ ] 相対パス規則が厳密に遵守されていること。
