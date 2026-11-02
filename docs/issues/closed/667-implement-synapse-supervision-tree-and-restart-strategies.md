---
ID: 667
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/ENH] Erlang/OTP 型スーパービジョンツリー (Supervision Tree) と再起動戦略 (one-for-one / all / rest) の実装 (ID: 667)

## 1. 概要 / Summary
Erlang/OTP の中核アーキテクチャであるスーパービジョンツリー（Supervision Tree, 階層型監視木）を uLisp / Synapse 並行基盤（[DSN-37 Section 8.4.3 & 14.8 Task 6.2](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）上に設計・実装する。
タスク間の階層的自律監視構造を導入し、子タスク異常終了時の 3 大再起動戦略（`one-for-one`, `one-for-all`, `rest-for-one`）と、短時間の頻繁なクラッシュループ（Flapping / Crash Loop）を検知して無限再起動・CPU 枯渇（CWE-400）を遮断する再起動頻度制限（MaxRestarts / MaxTime）および親スーパーバイザへの上位エスカレーション機構を提供する。

---

## 2. 背景と根本課題 / Background & Problem Statement
1. **プロセス障害からの自律的自己修復（Self-Healing）の欠如**:
   - 先行 Issue #666（リンク・モニタ・毒化）および Issue #668（Fail-Fast パニック・アリーナ O(1) リセット）により、タスクが安全にクラッシュし、メモリリーク 0 かつデッドロック 0 で脱出する基盤が完成した。
   - しかし、クラッシュしたタスクを「誰が・どのように・どの順序で再起動すべきか」という上位管理機構（Supervision）が存在せず、システム全体の長期間無人自律稼働が達成できない。
2. **協調タスク群における状態不整合（CWE-662）の防止**:
   - 密結合したパイプラインや協調ワーカー群において、1つのタスクがクラッシュした際にそのタスクだけを再起動すると、他の生存タスクとの間でプロトコル状態やシーケンス番号の不整合が生じる。
   - `one-for-all`（全員巻き添え再起動）や `rest-for-one`（依存後続タスク群のみ順次再起動）を選択可能にし、状態のクリーンリセットを保証する必要がある。
3. **Crash Loop / Flapping による CPU 資源枯渇（CWE-400）の遮断**:
   - 外部環境の恒常的障害（ネットワーク断絶、不正な設定等）に直面した際、子タスクが再起動直後に即座にパニックを繰り返すと、無限クラッシュループに陥り CPU を 100% 浪費する。
   - スライディング時間窓内で再起動回数が上限を超えた場合、当該スーパーバイザ自身が上位親へエスカレーションして安全に全体をアボート・隔離する機構が不可欠である。

---

## 3. トレーサビリティ / Traceability
- **関連設計書**: [DSN-37 ホスト・カーネル分離型 階層 CSP/アクター並行処理基盤 (Section 8.4.3, 14.8 Task 6.2)](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
- **関連 Issue**:
  - [Issue #630 (独立バンプアリーナ)](closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue #633 (線形所有権移譲チャネル)](closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue #635 (M:N ワークスティーリングスケジューラ)](closed/635-implement-synapse-work-stealing-scheduler.md)
  - [Issue #666 (タスク間リンク・モニタ・チャネル毒化)](closed/666-implement-synapse-task-links-and-monitors.md)
  - [Issue #668 (Fail-Fast パニック・アリーナ O(1) 即時破棄)](closed/668-implement-synapse-fail-fast-let-it-crash-semantics.md)
  - [Issue #669 (動的プロセス名レジストリ)](669-implement-synapse-process-registry-and-dynamic-rebinding.md)（本 Issue の後続）

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク詳細 | 緩和・防御策 |
| :--- | :--- | :--- |
| **CWE-400: Uncontrolled Resource Consumption** | 永続的障害入力により子タスクが毎秒数万回クラッシュ＆再起動を繰り返し、CPU およびメモリを枯渇させる | スライディング時間窓トラッカーによる `max-restarts` / `max-time` 制限を強制。上限超過時はスーパーバイザ自身が自爆し親へエスカレーション |
| **CWE-662: Improper Synchronization** | `one-for-all` 再起動時に旧タスクが完全に死ぬ前に新タスクが立ち上がり、チャネル通信が混信・競合する | 旧タスクの保有チャネルを即時毒化・解放し、タスク状態が `'terminated` に遷移したことを確認した上で新タスクを生成 |
| **CWE-833: Deadlock** | シャットダウン時や再起動時に、親スーパーバイザと子タスクの間で相互待機デッドロックが発生 | 単方向モニタ（`task-monitor`）ベースの非同期 DOWN メッセージ通知と、タイムアウト・即時毒化によるブロック解除 |
| **CWE-843: Type Confusion** | 不正な戦略シンボル（不正なアトムや整数等）や無効な child-spec がスーパーバイザに渡される | `child-spec?`, `supervisor-spec?`, `supervisor-context?` によるエントリポイント厳格型述語検査 |

---

## 5. アーキテクチャと詳細設計 / Architectural & Technical Design

### 5.1 データ構造の定義 (`supervisor.scm`)

#### 1. `<child-spec>` レコード
```scheme
(define-record-type <child-spec>
  (%make-child-spec id start-thunk restart-type shutdown-strategy child-type)
  child-spec?
  (id                child-spec-id)                ; シンボル (一意識別子)
  (start-thunk       child-spec-start-thunk)       ; 子タスク生成手続き (引数なし -> <task-context>)
  (restart-type      child-spec-restart-type)      ; 'permanent, 'transient, 'temporary
  (shutdown-strategy child-spec-shutdown-strategy) ; 'brutal_kill または タイムアウト(ms)
  (child-type        child-spec-child-type))       ; 'worker または 'supervisor
```

#### 2. `<supervisor-spec>` レコード
```scheme
(define-record-type <supervisor-spec>
  (%make-supervisor-spec strategy max-restarts max-time child-specs)
  supervisor-spec?
  (strategy     supervisor-spec-strategy)     ; 'one_for_one, 'one_for_all, 'rest_for_one
  (max-restarts supervisor-spec-max-restarts) ; 整数 (最大許容再起動回数)
  (max-time     supervisor-spec-max-time)     ; 整数 (時間窓)
  (child-specs  supervisor-spec-child-specs)) ; list of <child-spec>
```

#### 3. `<supervisor-context>` レコード
```scheme
(define-record-type <supervisor-context>
  (%make-supervisor-context spec supervisor-task children-box restart-history-box parent-supervisor state-box)
  supervisor-context?
  (spec                 supervisor-spec)
  (supervisor-task      supervisor-task)
  (children-box         %supervisor-children-box)         ; <atomic-box> holding ((<child-spec> . <task-context>) ...)
  (restart-history-box  %supervisor-restart-history-box)  ; <atomic-box> holding list of timestamps
  (parent-supervisor    supervisor-parent)
  (state-box            %supervisor-state-box))           ; 'running, 'stopping, 'stopped
```

### 5.2 3大再起動戦略（Restart Strategies）の動作仕様
1. **`one_for_one`**:
   - 死亡した当該子タスクのみを特定。
   - 旧タスクのリソース（アリーナ、チャネル）を完全破棄。
   - `start-thunk` を再実行して新品のタスクを生成し、リスト内の当該エントリのみを置換。再度 `task-monitor` を登録。
2. **`one_for_all`**:
   - グループ内のいずれかの子タスクが死亡した際、配下の全子タスクを逆順で停止（`task-exit!` / チャネル毒化）。
   - すべての旧タスクが停止したことを確認後、定義順に全子タスクを `start-thunk` で新品再生成。
3. **`rest_for_one`**:
   - 死亡した子タスクを `spec-list` 内で特定。
   - 当該子タスクおよび「その子タスクより後ろ（リストの後続）」に定義された全子タスクのみを逆順で停止。
   - 死亡タスク以降の後続タスク群のみを順次再起動（先行タスクは生存・稼働を継続）。

### 5.3 スライディング時間窓による Crash Loop 遮断
- 再起動実行時、現在論理時刻（タイムスタンプ）を `restart-history-box` に記録。
- `(- current-time max-time)` より古い過去のタイムスタンプをパージ。
- 残った履歴件数が `max-restarts` を超えた場合：
  - `(supervisor-stop! sup)` で配下の全子タスクを強制停止。
  - `(synapse-panic! 'shutdown_max_restarts_reached (supervisor-spec-strategy spec))` を発行し、上位スーパーバイザ（親）へクラッシュをエスカレーション。

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/667-synapse-supervision-tree`

### Step 1: スーパーバイザデータ構造とファクトリの実装
- 対象ファイル: `ulisp/runtime/concurrency/supervisor.scm`, `ulisp/lib/ulisp/concurrency/supervisor.sld`
- 実装内容:
  1. `<child-spec>`, `<supervisor-spec>`, `<supervisor-context>` のレコード定義と検証バリデータ。
  2. `make-child-spec`, `make-supervisor-spec`, `make-supervisor` ファクトリ手続き。

### Step 2: 子タスク起動と死活監視ループ
- 対象ファイル: `ulisp/runtime/concurrency/supervisor.scm`
- 実装内容:
  1. `supervisor-start-all-children!`: スペックリストに基づく子タスクの一括起動と `task-monitor` 登録。
  2. `supervisor-handle-down-message!`: DOWN メッセージ受信時のディスパッチと再起動戦略呼び出し。

### Step 3: 3大再起動戦略 (`one_for_one`, `one_for_all`, `rest_for_one`) の実装
- 対象ファイル: `ulisp/runtime/concurrency/supervisor.scm`
- 実装内容:
  1. `supervisor-restart-one-for-one!` の実装。
  2. `supervisor-restart-one-for-all!` の実装。
  3. `supervisor-restart-rest-for-one!` の実装。
  4. 旧タスクの完全クリーンアップ（`synapse-cleanup-task-resources!`）と新品アリーナ割り当て。

### Step 4: 再起動頻度トラッカーと Flapping 遮断
- 対象ファイル: `ulisp/runtime/concurrency/supervisor.scm`
- 実装内容:
  1. `supervisor-record-restart!`: スライディング時間窓の更新と閾値判定。
  2. 上限突破時の全子タスク安全停止と上位エスカレーション（`synapse-panic!`）。

### Step 5: 評価器・スケジューラ連携とテストスイート
- 対象ファイル: `ulisp/runtime/concurrency/eval_adapter.scm`, `tests/concurrency/test_supervisor.scm`, `ulisp/Makefile`
- 実装内容:
  1. Group 1: `one_for_one` 戦略による単一子タスクの自律復旧検証。
  2. Group 2: `one_for_all` 戦略による全子タスク巻き添え再起動検証。
  3. Group 3: `rest_for_one` 戦略による後続タスクのみの順次再起動検証。
  4. Group 4: 再起動種別（`permanent`, `transient`, `temporary`）の条件分岐検証。
  5. Group 5: Crash Loop 検知と上位親へのエスカレーション自爆（CWE-400 遮断）検証。
  6. Group 6: セキュリティ境界・CWE-843 型混同防御検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `one_for_one` 戦略において、クラッシュした子タスクのみが新品アリーナで再生成され、他子タスクが影響を受けないこと。
- [x] `one_for_all` 戦略において、1タスクの死で配下の全子タスクが安全に停止・再起動されること（状態不整合 CWE-662 排除）。
- [x] `rest_for_one` 戦略において、死亡タスクおよびその後に登録された後続タスク群のみが再起動されること。
- [x] 再起動種別（`permanent`, `transient`, `temporary`）に従い、正常終了時と異常終了時の再起動挙動が仕様通り制御されること。
- [x] スライディング時間窓内で再起動回数が上限を超えた際、無限ループにならず全子タスクを停止して親へエスカレーションすること（CWE-400 排除）。
- [x] `make -C ulisp test_supervisor`（全テスト PASS）および全並行性テスト群が 100% PASS すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。


