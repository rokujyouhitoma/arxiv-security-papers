---
ID: 666
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] Synapse タスク間双方向リンク (link)・単方向監視 (monitor) およびチャネル毒化防止機構の実装 (ID: 666)

## 1. 概要 / Summary
Erlang/OTP の耐障害性（Fault Tolerance）モデルに基づき、uLisp 並行処理基盤（Synapse Concurrency Runtime, DSN-37 Section 8.4.1 & 8.4.2）へタスク間の双方向運命共有（`task-link!`）および単方向監視（`task-monitor`）プリミティブを導入する。
さらに、通信相手タスクがクラッシュした際に対向待機タスクが `channel-recv!` または `channel-send!` で永久に起床されずデッドロック（CWE-833）に陥る事態を防ぐため、チャネル毒化（`channel-poison!` / Auto-Close）機構を確立し、待機中タスクを即時に安全脱出させる。

---

## 2. 背景と根本課題 / Background & Problem Statement
1. **障害伝播の欠如とゾンビタスクの残留**:
   - 現在の Synapse M:N スケジューラでは、協調動作する複数タスク（例: プロデューサ・コンシューマ・パイプラインステージ）のうち 1 つが異常終了（パニックや例外）しても、関連タスクに通知が伝播しない。
   - 結果として、正常に動作できない孤立タスクがゾンビとして残り、CPU 資源やメモリを浪費し続ける。
2. **チャネル待機中の永久ハング（CWE-833 Deadlock）**:
   - `channel-recv!` または `channel-send!` で相手の到着を待っている最中に通信相手タスクが死ぬと、チャネルの待機キューに登録されたタスクが二度と起床されず、システム全体が沈黙ハングする。
   - `channel-close!` は存在するが、受信側キューのみを起床し送信側が取り残される欠点があり、また「正常終了によるクローズ」と「異常死による毒化（Poisoning）」が区別されていない。
3. **スーパーバイザ構築の前提基盤の不足**:
   - 次フェーズ（Issue #667）で実装する Erlang/OTP 型スーパービジョンツリー（Supervision Tree: `one-for-one`, `one-for-all`, `rest-for-one`）は、子プロセスのクラッシュを検知する `task-monitor` / `task-link!` が不可欠である。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤 (Section 8.4.1, 8.4.2, 14.8 Task 6.1)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- **関連 Issue**:
  - [Issue #633 (線形所有権移譲チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #642 (世代管理型投機タスク破棄・世代ゲート)](closed/642-implement-synapse-epoch-fencing-distributed-rollback.md)
  - [Issue #675 (物理マルチコア並列実行エンジン)](closed/675-implement-synapse-native-multithread-worker-pool.md)
  - [Issue #667 (Supervision Tree & 再起動戦略)](667-implement-synapse-supervision-tree-and-restart-strategies.md)（本 Issue の後続）

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク詳細 | 緩和・防御策 |
| :--- | :--- | :--- |
| **CWE-833: Deadlock** | 通信相手タスクがクラッシュした際、チャネルで送受信待機中のタスクが永久に待機し続ける | タスク終了時に保有チャネルをアトミックに `CHANNEL_POISONED` 状態へ遷移させ、送受信両待機キュー内の全タスクを即座に `'poisoned` エラーでアンブロックして脱出させる |
| **CWE-362: Race Condition** | マルチコア並列実行下で、複数スレッドから同時にリンク登録・解除・シグナル送出が行われた際のデータ競合 | リンク・モニタ集合を `<atomic-box>` で保護し、アトミックな CAS（Compare-And-Swap）ループによるイミュータブルリスト更新を採用 |
| **CWE-400: Uncontrolled Resource Consumption** | 無制限な `task-link!` や `task-monitor` の呼び出しによるメモリ消費・DoS | タスクあたりの最大リンク数およびモニタ数を制限（デフォルト 1,024 件）し、超過時はエラーをスロー |
| **CWE-843: Type Confusion** | リンク・モニタ・チャネル操作に不正なオブジェクト（不正な TID、整数、文字列等）が渡される | `task-context?`, `channel?`, `integer?` による全公開 API のエントリポイント厳格型検証 |

---

## 5. アーキテクチャと詳細設計 / Architectural & Technical Design

### 5.1 データ構造の拡張

#### 1. `<task-context>` への耐障害性メタデータ統合 (`channel.scm`)
```scheme
(define-record-type <task-context>
  (%make-task-context tid state reductions continuation-pc stack-pointer
                      arena-base arena-offset arena-capacity
                      blocked-on epoch next-run
                      reduction-exhaustions steals-count handoff-box
                      links-box monitors-box monitored-by-box trap-exit-box owned-channels-box)
  task-context?
  ...
  (links-box          %task-links-box)           ; <atomic-box> holding list of linked <task-context>
  (monitors-box       %task-monitors-box)        ; <atomic-box> holding list of (<ref> . target-task)
  (monitored-by-box   %task-monitored-by-box)    ; <atomic-box> holding list of (<ref> . observer-ch)
  (trap-exit-box      %task-trap-exit-box)       ; <atomic-box> holding boolean (#t: trap, #f: cascade)
  (owned-channels-box %task-owned-channels-box)) ; <atomic-box> holding list of owned <channel>
```

#### 2. `<channel>` の状態拡張 (`channel.scm`)
```scheme
;; チャネル状態: 'open, 'closed, 'poisoned
(define (channel-poisoned? ch)
  (eq? (atomic-ref (%channel-state-box ch)) 'poisoned))

(define (channel-poison! ch reason)
  ;; 1. atomic-swap! で状態を 'poisoned へ不可逆遷移
  ;; 2. %channel-recv-wait-queue および %channel-send-wait-queue の全 waiter を即時起床
  ;; 3. 待機タスクへ (cons #f 'poisoned) を返却
  ...)
```

### 5.2 双方向リンク (`task-link!`, `task-unlink!`) とカスケード伝播 (`links.scm`)
- **`task-link! task-a task-b`**:
  - `task-a` の `links-box` に `task-b` を、`task-b` の `links-box` に `task-a` をアトミックに追加。
  - 既に終了しているタスクへリンクした場合、即座に相手の終了理由で自分自身に EXIT シグナルを送出。
- **`task-unlink! task-a task-b`**:
  - 両タスクの `links-box` から互いのアドレスを除去。
- **タスク終了時伝播 (`task-handle-termination! task reason`)**:
  - `links-box` に登録された各リンク先タスク `linked` に対し：
    - `(task-trap-exit? linked)` が `#f` かつ `reason` が `'normal` でない場合：
      - `linked` も同じ `reason` で即座に終了（カスケード終了・道連れ）。
    - `(task-trap-exit? linked)` が `#t` の場合：
      - `linked` のシグナル通知チャネル（または handoff / mailbox）へ `'(EXIT <from-tid> <reason>)` を配送。

### 5.3 単方向監視 (`task-monitor`, `task-demonitor`) と DOWN 通知 (`links.scm`)
- **`task-monitor observer-task target-task [notify-channel]`**:
  - 一意な監視参照 `<ref>`（`allocate-monitor-ref!`）を生成。
  - `target-task` の `monitored-by-box` に `(<ref> observer-tid notify-channel)` を登録。
  - 戻り値として `<ref>`（Fixnum または Record）を返却。
- **`task-demonitor ref`**:
  - 当該 `<ref>` の監視登録を解除。
- **DOWN 通知配送**:
  - `target-task` が終了した際（正常・異常問わず）：
    - `notify-channel` へ `(list 'DOWN ref 'process (task-tid target-task) reason)` を非同期 enqueue。

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/666-synapse-task-links-and-monitors`

### Step 1: チャネル毒化（Poisoning）および全待機キュー起床の実装
- 対象ファイル: `ulisp/runtime/concurrency/channel.scm`, `ulisp/lib/ulisp/concurrency/channel.sld`
- 実装内容:
  1. `channel-poison!` および `channel-poisoned?` の実装。
  2. チャネル毒化時に `send-wait-queue` と `recv-wait-queue` の全ウェイターをアンブロックし、待機側で `(cons #f 'poisoned)` を返却して即座に脱出させる。
  3. `channel-register-owner-task!` / `channel-unregister-owner-task!` によるタスク-チャネル関連付け基盤の整備。

### Step 2: `<task-context>` 耐障害性メタデータの拡張
- 対象ファイル: `ulisp/runtime/concurrency/channel.scm`, `context.scm`
- 実装内容:
  1. `links-box`, `monitors-box`, `monitored-by-box`, `trap-exit-box`, `owned-channels-box` のフィールド追加と初期化。
  2. アクセサおよびミューテータの実装。

### Step 3: タスクリンク・モニタコアエンジン (`links.scm`) の新設
- 対象ファイル: `ulisp/runtime/concurrency/links.scm`, `ulisp/lib/ulisp/concurrency/links.sld`
- 実装内容:
  1. `allocate-monitor-ref!` による一意な参照番号採番器。
  2. `task-link!`, `task-unlink!`, `task-linked?` のアトミック実装。
  3. `task-monitor`, `task-demonitor` の実装と DOWN メッセージ構築。
  4. `task-trap-exit!`, `task-trap-exit?` によるトラップフラグ制御。
  5. `task-terminate-with-signals!` による終了ハンドラと、保有チャネルの自動毒化（Auto-Poison）。

### Step 4: スケジューラ統合 (`scheduler.scm`)
- 対象ファイル: `ulisp/runtime/concurrency/scheduler.scm`
- 実装内容:
  1. タスク実行完了時（`scheduler-execute-task!`）および例外捕捉時における `task-terminate-with-signals!` の自動フック呼び出し。
  2. クラッシュしたタスクのアリーナ解放と連鎖終了タスクのデックからのパージ。

### Step 5: テストスイート拡充と品質ゲート検証
- 対象ファイル: `tests/concurrency/test_links_monitors.scm`, `ulisp/Makefile`
- 実装内容:
  1. Group 1: `task-link!` 双方向リンクと正常終了時の非連鎖検証。
  2. Group 2: `task-link!` 異常終了時の道連れカスケード終了（ゾンビ排除）検証。
  3. Group 3: `task-trap-exit!` による EXIT シグナル捕捉・メッセージ変換検証。
  4. Group 4: `task-monitor` / `task-demonitor` による DOWN 通知配送検証。
  5. Group 5: チャネル送受信待機中における対向タスククラッシュ時の毒化脱出（デッドロック完全防止）検証。
  6. Group 6: セキュリティ境界・CWE-843/CWE-400 ガード検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `task-link!` で結ばれたタスクの一方がクラッシュした際、`trap-exit` されていないリンク先タスクが確実に道連れ終了すること。
- [x] `task-trap-exit!` が有効なタスクは道連れ終了せず、`'(EXIT <from-tid> <reason>)` シグナルメッセージを受信できること。
- [x] `task-monitor` により、監視対象タスクの終了理由（`'normal`, `'panic`, `'error` 等）が監視元の通知チャネルへ `'(DOWN <ref> process <target-tid> <reason>)` として確実に配送されること。
- [x] `channel-send!` または `channel-recv!` で待機中に対向タスクがクラッシュした場合、チャネルが `CHANNEL_POISONED` となり、デッドロックすることなく即座に脱出・エラー処理されること（CWE-833 排除）。
- [x] 複数ネイティブワーカー（物理マルチコア）環境下で、リンク・モニタ操作の並行競合（CWE-362）が発生しないこと。
- [x] `make -C ulisp test_links_monitors` (全テスト PASS), `test_multithread_scheduler`, `test_scheduler` が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。
