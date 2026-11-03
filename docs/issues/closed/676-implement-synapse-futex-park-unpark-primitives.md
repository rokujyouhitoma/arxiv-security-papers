---
ID: 676
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Linux SYS_futex に基づくワーカー待機 (Park) およびチャネル起床 (Unpark) による省電力・低遅延同期機構の実装 (ID: 676)

## 1. 概要 / Summary
現在の Synapse M:N スケジューラにおけるタスク枯渇時のバックオフ処理（`%scheduler-idle-backoff!`）は 64 回のビジースピンループを行っている。
マルチコア並行環境下で仕事のないワーカーがスピンを続けると、CPU コアの無駄な電力消費とメモリバスのキャッシュコヒーレンシ帯域（Cache Invalidation / Snoop Traffic）を激しく圧迫し、実行中ワーカーのメモリアクセス性能を著しく低下させる（CWE-400）。
Linux カーネルの `SYS_futex`（syscall 202, `FUTEX_WAIT_PRIVATE` / `FUTEX_WAKE_PRIVATE`）を活用した OS レベルの待機（Park）および起床（Unpark）プリミティブを実装し、タスク枯渇ワーカーを即座に省電力スリープ（CPU 使用率 0%）させ、チャネルメッセージ送信（`channel-send!`）や新規タスク生成（`scheduler-spawn!`）時にマイクロ秒未満で即時起床させる極限のハードウェア協調同期基盤を確立する。

---

## 2. 背景と根本課題 / Background & Problem Statement
1. **アイドルワーカーによる CPU 飽和とメモリバス帯域圧迫 (CWE-400)**:
   - 仕事がないワーカースレッドがビジースピンを継続すると、全コアが 100% 負荷となり、サーバーの消費電力を激増させるだけでなく、L1/L2/L3 キャッシュ無効化ラインのバス競合を発生させ、実際に有益な計算を行っているアクティブワーカーのスループットを 30〜50% 阻害する。
2. **Lost Wakeup（起床漏れ・永久デッドロック CWE-833）の防止**:
   - 単純な `sleep` や条件変数では、ワーカーが「スリープに入る直前」に他スレッドからタスクが投入された際、起床通知が空振りし、ワーカーが永久に起床しなくなるレースコンディション（Lost Wakeup）が発生しやすい。
   - `EMPTY` (0) / `PARKED` (1) / `NOTIFIED` (2) の 3 状態アトミック遷移モデルと `SYS_futex` のカーネル値比較検証（`*uaddr == expected_val` のアトミックチェック）を融合し、起床通知の先行到着時でもスリープを即時バイパスする安全機構が必要である。
3. **偽共有（False Sharing）の完全排除**:
   - 複数ワーカーの futex 変数が同一キャッシュライン（64バイト）上に隣接して配置されると、1つのワーカーの Park/Unpark によるキャッシュ無効化が他ワーカーの待機を不要に妨害する。
   - 各ワーカーの futex 単語は 64 バイト（キャッシュライン境界）でアラインされた独立メモリセルとして割り当て、真のマルチコアスケーラビリティを確保する。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤 (Section 7.4.2 & Section 14.9 Task 7.2)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- **関連 Issue**:
  - [Issue #633 (第一級 P2P チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #675 (物理マルチコア並列実行エンジン)](closed/675-implement-synapse-native-multithread-worker-pool.md)
  - [Issue #666 (タスク間リンク・モニタ・チャネル毒化)](closed/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #668 (Fail-Fast パニック・アリーナ O(1) 即時破棄)](closed/668-implement-synapse-fail-fast-let-it-crash-semantics.md)
  - [Issue #667 (Erlang/OTP 型スーパービジョンツリー)](closed/667-implement-synapse-supervision-tree-and-restart-strategies.md)

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク詳細 | 緩和・防御策 |
| :--- | :--- | :--- |
| **CWE-400: Uncontrolled Resource Consumption** | タスク枯渇時にアイドルワーカーがビジーループを続け、全 CPU コアを 100% 占有しメモリバス帯域を浪費 | `SYS_futex`（`FUTEX_WAIT_PRIVATE`）によりカーネルレベルでスレッドを省電力休止（CPU 使用率 0%）させ、電力・帯域浪費を完全遮断 |
| **CWE-833: Deadlock (Lost Wakeup)** | ワーカーがスリープ直前に通知を受け取り、通知が消失して永久待機に陥る | `EMPTY` (0), `PARKED` (1), `NOTIFIED` (2) の 3 状態 CAS モデルと futex 値一致時のみスリープするカーネルアトミック検証により Lost Wakeup を 100% 排除 |
| **CWE-125 / CWE-787: Out-of-bounds Read / Write** | 不正なポインタや非アラインメモリアドレスを `SYS_futex` に渡しカーネルエラー（`EFAULT`/`EINVAL`）や異常停止 | 64 バイト（キャッシュライン）アラインされた専用 futex セルを確保・管理し、エントリポイントでの厳格なアライメント・ポインタ検証を実施 |
| **CWE-843: Type Confusion** | `futex-wait` / `futex-wake` / `park` / `unpark` に不正なオブジェクトが渡された際の型混同 | 全公開 API のエントリポイントで `integer?`, `futex-cell?`, `worker-context?` 等の厳格な型述語チェックを実施 |

---

## 5. アーキテクチャと詳細設計 / Architectural & Technical Design

### 5.1 AMD64 Linux ネイティブ Futex コア (`futex.s`)
- **システムコール番号**: 202 (`SYS_futex`)
- **操作フラグ**:
  - `FUTEX_WAIT_PRIVATE = 128` (プロセス内高速待機)
  - `FUTEX_WAKE_PRIVATE = 129` (プロセス内高速起床)
- **提供関数 (System V AMD64 ABI)**:
  1. `ulisp_futex_wait(u32 *addr, int expected_val, int timeout_ms)`:
     - タイムアウト指定時はスタック上に `struct timespec { sec, nsec }` を構築して `r10` に設定。
     - 戻り値: `0` (正常起床), `1` (値不一致 EAGAIN), `2` (タイムアウト ETIMEDOUT), `-1` (エラー)。
  2. `ulisp_futex_wake(u32 *addr, int count)`:
     - 指定個数（通常 1 または `INT_MAX`）のスレッドを起床。
     - 戻り値: 起床されたスレッド数（整数）。
  3. `ulisp_alloc_futex_cell()`:
     - 64 バイト（キャッシュライン）アラインされた 32bit futex 単語メモリを安全に割り当て、アドレスを返却。False Sharing を完全排除。
  4. `ulisp_free_futex_cell(u32 *addr)`:
     - メモリの安全な解放。
  5. `ulisp_futex_get(u32 *addr)` / `ulisp_futex_set(u32 *addr, int val)`:
     - 32bit アトミック読み込み / 書き込み。

### 5.2 3 状態 Park / Unpark 抽象化レイヤー (`futex.scm`)
```scheme
;; 状態定数
(define *futex-empty*    0) ; アイドル（通知なし）
(define *futex-parked*   1) ; スレッドが futex で待機中
(define *futex-notified* 2) ; 未消費の起床通知あり

;; 1. ワーカー待機 (park)
(define (futex-park! cell timeout-ms)
  ;; 状態が NOTIFIED なら消費して即座にリターン（スリープ不要！）
  (if (atomic-cas! cell *futex-notified* *futex-empty*)
      #t
      (begin
        ;; 状態を PARKED に設定
        (atomic-set! cell *futex-parked*)
        ;; futex_wait(cell, PARKED, timeout) を呼び出し
        (let ((rc (ulisp-futex-wait (futex-cell-addr cell) *futex-parked* timeout-ms)))
          ;; 起床後、状態を EMPTY にリセット
          (atomic-set! cell *futex-empty*)
          rc))))

;; 2. ワーカー起床 (unpark)
(define (futex-unpark! cell)
  (let ((prev (atomic-swap! cell *futex-notified*)))
    (if (= prev *futex-parked*)
        ;; 待機中だった場合のみカーネルシステムコールで起床
        (ulisp-futex-wake (futex-cell-addr cell) 1)
        0)))
```

### 5.3 スケジューラ統合 (`scheduler.scm`)
1. `<worker-context>` に `futex-cell` を配備。
2. `%scheduler-worker-native-loop`:
   - 全キューからのワークスティールが失敗した際、短いスピン（32回 PAUSE）を経て `(futex-park! worker-futex-cell 100)` でスリープ。
3. `scheduler-spawn!` / `channel-send!`:
   - 新規タスク投入時またはチャネルへのメッセージ送信時、休止中のワーカーの `futex-cell` に対し `(futex-unpark! worker-futex-cell)` を発行して即時起床。

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/676-futex-park-unpark-primitives`

### Step 1: AMD64 ネイティブ Futex アセンブリ (`futex.s`) の実装
- 対象ファイル: `ulisp/runtime/concurrency/futex.s`, `ulisp/Makefile`
- 実装内容:
  1. `ulisp_futex_wait`, `ulisp_futex_wake` の `SYS_futex` (202) システムコール実装。
  2. 64 バイトアラインされた `ulisp_alloc_futex_cell`, `ulisp_free_futex_cell`。
  3. `Makefile` に `build/futex.o` のビルド規則を追加し、テストバイナリにリンク。

### Step 2: Scheme Park / Unpark 抽象化レイヤー (`futex.scm` & `futex.sld`)
- 対象ファイル: `ulisp/runtime/concurrency/futex.scm`, `ulisp/lib/ulisp/concurrency/futex.sld`
- 実装内容:
  1. `<futex-cell>` レコード定義と述語・アクセサ。
  2. 3 状態（`EMPTY`, `PARKED`, `NOTIFIED`）に基づく `futex-park!` および `futex-unpark!` の実装。
  3. タイムアウト付き待機と Lost Wakeup 防止の完全保証。

### Step 3: スケジューラ統合と省電力ワーカー待機
- 対象ファイル: `ulisp/runtime/concurrency/scheduler.scm`, `ulisp/lib/ulisp/concurrency/scheduler.sld`
- 実装内容:
  1. `<worker-context>` への `futex-cell` 追加。
  2. ネイティブワーカーループでのアイドル時 `futex-park!` 呼び出し。
  3. `scheduler-spawn!` およびチャネル起床時の `futex-unpark!` 発行。

### Step 4: テストスイート拡充と品質ゲート検証
- 対象ファイル: `tests/concurrency/test_futex.scm`, `ulisp/Makefile`
- 実装内容:
  1. Group 1: `ulisp_futex_wait` & `ulisp_futex_wake` 基本システムコール動作検証。
  2. Group 2: 3 状態 Park / Unpark セマンティクスと先行通知（Lost Wakeup 排除）検証。
  3. Group 3: タイムアウト付き待機（指定時間後の自律復帰）検証。
  4. Group 4: スケジューラ統合・タスク不在時のワーカー省電力休止とタスク投入時の即時起床検証。
  5. Group 5: 複数ワーカー並列待機時の一括起床（`wake-all`）検証。
  6. Group 6: セキュリティ境界・CWE-843 型混同防御検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `SYS_futex` (202) を用いた `ulisp_futex_wait` および `ulisp_futex_wake` が AMD64 Linux 上で正常に機能すること。
- [x] `futex-park!` と `futex-unpark!` による 3 状態同期モデルが、先行通知時のスリープバイパス（Lost Wakeup 排除）を 100% 保証すること（CWE-833 排除）。
- [x] タイムアウト付き待機において、指定ミリ秒経過後に確実に自律起床すること。
- [x] スケジューラのワーカーがタスク不在時にビジースピンを停止して省電力休止し、タスク生成時に即座に起床・実行再開すること（CWE-400 排除）。
- [x] `make -C ulisp test_futex`（全テスト PASS）および全並行性テスト群（`test_scheduler`, `test_multithread_scheduler`, `test_links_monitors`, `test_let_it_crash`, `test_supervisor`, `test_preemption`, `test_eval_adapter`, `test_concurrency_harness`）が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。


