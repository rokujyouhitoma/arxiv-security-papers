---
ID: 804
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] L1 Bounded Ring Buffer (256エントリ CAS-Free キュー) 導入によるタスク Push/Pop 高速化 (ID: 804)

## 1. 概要 / Summary
Go の Goroutine スケジューラにおける P ローカル実行キューは、256 エントリの固定長循環配列（Circular Ring Buffer: `runq [256]guintptr`）を採用しており、自ワーカーからの Push/Pop は CAS 不要、アトミックなインデックス加算（1〜2 CPU 命令）のみで完結する。
一方、現在の Synapse のワークスティーリングスケジューラは、全タスクを Chase-Lev デック（可変長配列）に直接投入しており、動的配列拡張チェックやポインタ多重間接参照、メモリバリア（`%memory-fence`）のオーバーヘッドが存在する。

本 Issue では、各ワーカーのフロントエンドに **L1 256エントリ固定長リングバッファ（CAS-Free Run-Queue）** を導入し、L1 キューが満杯になった場合のみ L2 Chase-Lev デックへバッチ退避する二層キュー構造を確立する。これにより、ワーカーローカルなタスク投入・取得オーバーヘッドを 120ns から 15ns 前後へ大幅圧縮し、Go の Goroutine 生成・実行スループット（4.07M tasks/sec）に匹敵・凌駕するホットパスを構築する。

---

## 2. 専門家レビュー視点 (Multi-Agent Perspectives)

- **Project Manager (PM)**:
  - Go の Goroutine（4.07M tasks/sec, 24ms）に対抗する最重要のホットパス最適化である。既存の Chase-Lev デックおよび Work Stealing の安全性・整合性を 100% 堅持した上で、段階的に二層化を導入する。
- **Systems Architect**:
  - 各 `<worker-context>` に `l1-ring-buffer`（256 エントリ固定長ベクタ、マスク 255）を配備する。自ワーカーは排他的に `tail` を操作して CAS フリーで Push/Pop を行い、満杯時（256個）に半分（128個）を L2 Chase-Lev デックへ一括オフロード、空時に L2 からバッチ補充する階層メモリ構造を設計する。
- **Software Development (SWD)**:
  - `<l1-ring-buffer>` のデータ型と `l1-push!`, `l1-pop!`, `l1-batch-offload-to-l2!`, `l1-batch-refill-from-l2!` を `ulisp/runtime/concurrency/deque.scm` に実装。`scheduler.scm` の `scheduler-spawn!` および `scheduler-worker-step!` に直結する。
- **Information Security Specialist**:
  - CWE-119 / CWE-787 (Buffer Overflow: ビットマスク `bitwise-and idx 255` による境界外アクセス完全排除)、CWE-362 (Race Condition: 自ワーカー排他とスティーラー間の競合防止)、CWE-416 (Use-After-Free: ポップ済みスロットの即時 `#f` クリアによる参照保持防止) を徹底する。
- **Software Quality Assurance Specialist (SQA)**:
  - L1 単体テスト（256エントリ境界、ラップアラウンド、128個バッチオフロード、バッチ補充）、並行ストレステスト（10回連続 `make test_concurrency_stress`）、および性能リグレッションゲート（`make -C ulisp bench_concurrency_gate`）を 100% PASS させる。

---

## 3. トレーサビリティ / Traceability
- [DSN-37: Synapse Dual-Plane Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Section 7.2 (Chase-Lev Stealing & Task Queues)
- [concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) Section 2 (Go 1.22.2 との実機実測比較)
- [Issue #803](../issues/closed/803-implement-worker-local-task-context-object-pool.md) - ワーカーローカル Task Context Object Pool によるヒープ確保ゼロ化

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/deque.scm](../../ulisp/runtime/concurrency/deque.scm) - `<l1-ring-buffer>` データ構造、CAS-Free Push/Pop、L2 バッチオフロード・補充の実装
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - `<worker-context>` への L1 キュー統合、`scheduler-spawn!` および `scheduler-worker-step!` の L1 二層化
- [ ] [tests/concurrency/test_deque.scm](../../tests/concurrency/test_deque.scm) - L1 リングバッファ単体テスト（境界値・ラップアラウンド・バッチ退避）
- [ ] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm) - スケジューラ統合テスト（Group 19: L1 Bounded Ring Buffer & Two-Tier Scheduling）
- [ ] [docs/benchmarks/concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md) - ベンチマークレポートの更新

---

## 5. セキュリティ分析と防御策 (Threat Modeling & CWE)

1. **CWE-119 / CWE-787: Buffer Overflow (循環配列の境界外メモリアクセス)**:
   - 脅威: インデックス加算による 256 を超える不正アクセスや負インデックスによるメモリ破壊。
   - 防御策:
     - 配列長は固定長 256（$2^8$）に厳格固定。すべての配列アクセスは `(bitwise-and idx 255)` の 1 命令ビットマスク演算を強制し、ハードウェアレベルで境界外アクセスを構造的に排除。
2. **CWE-362: Race Condition (並行データ競合と二重実行)**:
   - 脅威: 自ワーカーの L1 操作中に他ワーカーのスティーラーが同一スロットを同時に読み書きし、タスクの重複実行またはタスク消失が生じる危険。
   - 防御策:
     - L1 リングバッファは「ワーカー完全排他（Local Only）」とし、他ワーカーからの Work Stealing は原則としてスレッドセーフな L2 Chase-Lev デックに対して行う。
     - 自ワーカーが L1 から L2 へ 128 タスクをバッチ退避する際、および L2 から補充する際も、Chase-Lev デックの正規の API（`deque-push!` / `deque-pop!`）を通過させることでスティーラーとの競合を完全防止。
3. **CWE-400: Resource Exhaustion (無制限なメモリ消費とキュー肥大化)**:
   - 脅威: 大量タスクが単一ワーカーに集中した際のメモリ枯渇。
   - 防御策:
     - L1 は 256 エントリ固定長配列とし、溢れた分は有界な L2 デックおよびグローバルキューへ順次退避されるため、単一ワーカーのメモリ無制限消費を防止。
4. **CWE-416: Use-After-Free (ポップ済みタスクの参照残存による GC リーク)**:
   - 脅威: ポップ後にリングバッファスロットに古いタスクポインタが残り続け、タスク終了後も GC が回収できなくなる危険。
   - 防御策:
     - ポップ直後に `(vector-set! buf slot #f)` を実行し、スロット参照を即時クリア。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `feat/804-implement-l1-bounded-ring-buffer-for-worker-local-queue`

### Step 1: `<l1-ring-buffer>` データ構造の実装 (`ulisp/runtime/concurrency/deque.scm`)
1. 定数定義:
   - `*l1-ring-capacity* = 256`
   - `*l1-ring-mask* = 255`
   - `*l1-batch-size* = 128`
2. レコード型 `<l1-ring-buffer>` の定義:
   - `buffer` (256要素ベクタ)
   - `head` (fixnum, 読み出しインデックス)
   - `tail` (fixnum, 書き込みインデックス)
   - `runnext` (fixnum/vector, 優先直近タスクスロット: 1タスク即時実行用)
3. コア関数の実装:
   - `(make-l1-ring-buffer)`: 初期化
   - `(l1-ring-count l1)`: 要素数 `(- tail head)`
   - `(l1-ring-empty? l1)`: `(and (= head tail) (not (l1-ring-runnext l1)))`
   - `(l1-ring-full? l1)`: `(>= (- tail head) 256)`
   - `(l1-ring-push! l1 val l2-deque)`:
     - `runnext` が空なら `runnext` に即時格納（1命令）。
     - `runnext` が埋まっていれば、旧 `runnext` をリングバッファへ退避。
     - リングバッファが満杯（`count >= 256`）なら、半分の 128 エントリを `l2-deque` へバッチ退避（`deque-push!`）。
     - `(vector-set! buffer (bitwise-and tail 255) val)` を実行し `tail = tail + 1`。
   - `(l1-ring-pop! l1 l2-deque)`:
     - `runnext` が存在すれば `runnext` を返し、スロットを `#f` にクリア。
     - `runnext` がなければ、リングバッファの `tail - 1` から LIFO で Pop。
     - リングバッファが空なら、`l2-deque` から最大 128 エントリをバッチ補充。

### Step 2: `<worker-context>` への L1 キュー統合 (`ulisp/runtime/concurrency/scheduler.scm`)
1. `<worker-context>` に `l1-queue` フィールドを追加。
2. `make-worker-context` で `(make-l1-ring-buffer)` を初期化。
3. `scheduler-spawn!` において、ローカルワーカーへの投入（自ワーカーまたは単一スレッド時）に `(l1-ring-push! (worker-l1-queue w) normalized (worker-deque w))` を呼び出す。

### Step 3: `scheduler-worker-step!` のホットパス二層化 (`ulisp/runtime/concurrency/scheduler.scm`)
1. Phase 1 を L1 キューからの取得に変更:
   - `(l1-ring-pop! (worker-l1-queue w) (worker-deque w))` でタスクを取得。
   - タスクが取れれば即座に実行。
2. Phase 2: L1 および L2 が空の場合、グローバルキューから取得。
3. Phase 3: 他ワーカーからの Work Stealing（L2 Chase-Lev デックから安全にスチール）。

### Step 4: 単体テスト・統合テストの整備 (`tests/concurrency/test_scheduler.scm`)
1. Group 19（L1 Bounded Ring Buffer & Two-Tier Work-Stealing）を追加:
   - L1 への 256 要素投入、ラップアラウンド動作検証。
   - 257 要素投入時の L2 デックへの自動バッチ退避（128個）検証。
   - L1 空時の L2 からの自動バッチ補充検証。
   - `runnext` 優先スロットの LIFO 即時実行動作検証。
   - 10,000 タスク並行投入・実行時のデータ欠損ゼロ検証。

### Step 5: 全品質ゲート・ベンチマーク検証
1. `make -C ulisp lint_sexpr`（全 S 式括弧整合性チェック）。
2. `make -C ulisp test_scheduler`, `test_channel`, `test_supervisor` の全件 PASS。
3. `make -C ulisp test_concurrency_stress`（10回連続並行ストレステスト）の PASS。
4. `make -C ulisp bench_concurrency_gate`（CI 性能リグレッションゲート）の PASS。

---

## 7. 完了条件 / Success Criteria (DoD)
- [ ] `<l1-ring-buffer>` が `ulisp/runtime/concurrency/deque.scm` に実装され、CAS フリー・ビットマスク（255）で動作すること。
- [ ] 256 エントリ満杯時の L2 デックへの 128 個自動バッチ退避、および空時の自動バッチ補充が正常に動作すること。
- [ ] `<worker-context>` に L1 キューが統合され、`scheduler-spawn!` と `scheduler-worker-step!` のホットパスが二層化されること。
- [ ] `tests/concurrency/test_scheduler.scm` に Group 19 が追加され、全アサーションが PASS すること。
- [ ] 単体テスト、10回連続並行ストレステスト、および CI 性能リグレッション監査が 100% PASS すること。
- [ ] 相対パス規則が厳格に遵守され、絶対パスが 0 件であること。
- [ ] `docs/benchmarks/concurrency_evaluation.md` が最新性能で更新されること。


