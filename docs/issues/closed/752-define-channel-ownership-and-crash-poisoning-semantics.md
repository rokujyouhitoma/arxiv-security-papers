---
ID: 752
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-11-07
関連 Issue: #731, #668, #723, #725, #741, #750, #751
---

# [FEAT/SEC] チャネル所有権セマンティクスおよびクラッシュ時自動汚染範囲の仕様策定・実装 (ID: 752)

## 1. 概要 / Summary

Synapse 並行性ランタイムにおいて、チャネル（`<channel>`）は生成タスク（`current-synapse-task`）の所有リソース（`owned-channels-box`）として自動登録され（Issue #731）、タスク終了時に一括して毒化（`task-poison-owned-channels!`）される。

しかし、現在の実装（[`ulisp/runtime/concurrency/channel.scm`](../../../ulisp/runtime/concurrency/channel.scm) および [`ulisp/runtime/concurrency/links.scm`](../../../ulisp/runtime/concurrency/links.scm)）には以下の2つの重大な設計的欠陥と脆弱性が存在する：

1. **正常終了時の不当な道連れ毒化 (CWE-703 / False Cascading Failure)**:
   タスクが正常完了（`reason == 'normal'`）して終了した場合であっても、`task-handle-termination!` は所有チャネルを無条件に `channel-poison!` で毒化する。
   このため、送信タスクがバッファにメッセージを残して正常終了した際、受信側タスクが残存メッセージを読み切る（Graceful Drain）前にチャネルが異常破壊され、受信側が `poisoned` 例外で意図せずクラッシュする。
2. **所有権移転（Ownership Transfer / Disown）機構の欠如 (CWE-662 / Spurious Resource Cleanup)**:
   パイプラインやスーパーバイザー構成において、タスク A が初期化時にチャネルを生成し、ワーカータスク B や C に引き渡したとする。タスク A が初期化処理を終えて終了（またはクラッシュ）すると、チャネルがタスク A に紐付いたままであるため、現在タスク B/C 間で稼働中の通信チャネルが問答無用で破壊される。

本 Issue では、Erlang/OTP のメッセージパッシングの独立性および Rust/Go のチャネルセマンティクスに準拠した **厳格なチャネル所有権モデル（Ownership & Transfer Model）** を策定・実装する。
具体的には、**明示的な所有権移転（`channel-transfer-ownership!`）**、**特定タスクに縛られない独立共有チャネル化（`channel-disown!` / `channel-share!`）**、および **正常終了時の Graceful Close（残存メッセージドレイン許容）とクラッシュ時の Crash Poisoning（デッドロック防止）の明確な分離** を確立する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Denial of Service (DoS)** / False Cascade | **CWE-703**: Improper Handling of Exceptional Conditions | High | 送信タスクが正常完了（`normal`）したにもかかわらずチャネルが毒化（`poisoned`）され、下流のコンシューマタスクがパニックを引き起こしてパイプライン全体が異常終了・サービス停止に至る。 |
| **Integrity Violation (整合性侵害)** | **CWE-662**: Insufficient Synchronization / Spurious Resource Destruction | High | 初期化タスクが子タスク間通信チャネルを作成して引き渡した後、初期化タスクの終了に伴い稼働中のチャネルが破壊され、子タスクが通信不能に陥る。 |
| **Deadlock (デッドロック)** | **CWE-833**: Resource Deadlock | High | 所有権移転や共有化を導入した際に、送信タスクの異常クラッシュ（panic）時にチャネル毒化が行われないと、受信側が永久ブロックしてシステム停止を招く（DSN-37 Section 8.4.2 の担保が必須）。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が存在しているか
1. **正常終了と異常終了の無差別毒化 (`links.scm` L242-244, `channel.scm` L890-903)**:
   `task-handle-termination!`（`links.scm`）において、終了理由 `safe-reason` が `'normal` であるかどうかにかかわらず、常に `(task-poison-owned-channels! task safe-reason wake-hook)` を実行し、全チャネルを `channel-poison!` している。
   Go や Rust、POSIX パイプでは、ライター終了時は EOF（クローズ）であり、バッファ内のデータは読み切ることが保証されるべきである。
2. **チャネル所有者メタデータの単方向性**:
   `<task-context>` 側には `owned-channels-box`（タスクが所有するチャネル一覧）があるが、`<channel>` 側には自身を所有するタスク（`owner-box`）への参照がなく、また所有権を別のタスクに移譲したり所有権を解除する API が一切存在しなかった。

---

## 4. 恒久対策アーキテクチャ設計 (Channel Ownership & Lifecycle Semantics)

### 4.1 チャネル所有権モデルの仕様
1. **初期所有者 (Initial Owner)**:
   - `make-channel` / `make-spsc-channel` 生成時、呼び出し元コンテキスト `(current-synapse-task)` が存在すれば、そのタスクをチャネルの初期所有者として登録。
   - タスクコンテキスト外で生成されたチャネルは `owner = #f`（独立共有チャネル / Unowned Channel）。
2. **所有権の移転 (`channel-transfer-ownership!`)**:
   - `(channel-transfer-ownership! ch target-task)`:
     チャネルの所有権を現在の所有者から `target-task` へアトミックに移譲する。
     - 旧所有者タスクの `owned-channels-box` から `ch` を除去（`task-unregister-channel!`）。
     - `target-task` の `owned-channels-box` に `ch` を追加（`task-register-channel!`）。
     - チャネルの `owner-box` を `target-task` に更新。
   - `(channel-transfer! ch from-task to-task)`: 送信元・送信先タスクを明示指定した移転。
3. **共有・独立チャネル化 (`channel-disown!` / `channel-share!`)**:
   - `(channel-disown! ch)` / `(channel-share! ch)`:
     現在の所有者タスクからチャネルを切り離し、`owner = #f` とする。
     - 特定タスクの生死に一切道連れにされず、明示的な `channel-close!` または GC によってのみ管理される共有通信路となる。
4. **所有者照会**:
   - `(channel-owner ch)`: 現在の所有タスク（`<task-context>` または `#f`）を返す。

### 4.2 終了時のライフサイクル動作（正常クローズ vs クラッシュ毒化）
タスク終了処理（`task-cleanup-owned-channels!` / `task-handle-termination!`）において：
- **正常終了 (`reason == 'normal'`)**:
  - 所有チャネルに対して `channel-close! ch`（正常クローズ）を実行する。
  - **Graceful Drain 保証**: チャネルバッファに残存しているメッセージは、コンシューマが EOF（`'closed`）に達するまで正常に読み切ることができる。
  - 送信待機キューでブロック中のタスクは解除される。
- **異常終了・クラッシュ (`reason != 'normal'`, 例: `panic`, `killed`, `timeout`)**:
  - 所有チャネルに対して `channel-poison! ch reason wake-hook`（毒化）を実行する。
  - 受信・送信待機中のすべてのタスクを即座に起床させ、デッドロック（CWE-833）を防止する。
- **独立チャネル (`owner == #f`)**:
  - いずれのタスクの終了時にもクローズ・毒化されない。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`ulisp/runtime/concurrency/channel.scm`](../../../ulisp/runtime/concurrency/channel.scm):
  - `<channel>` レコードに `owner-box` フィールドを追加
  - `%make-channel-instance` における `owner-box` 初期化
  - `channel-owner` アクセサの実装
  - `channel-transfer-ownership!`, `channel-transfer!` の実装
  - `channel-disown!`, `channel-share!` の実装
  - `task-poison-owned-channels!` の改修（正常終了時の `channel-close!`、異常終了時の `channel-poison!` の分離）
  - 新規プロシージャ `task-cleanup-owned-channels!` の追加
- [x] [`ulisp/runtime/concurrency/links.scm`](../../../ulisp/runtime/concurrency/links.scm):
  - `task-handle-termination!` における `task-cleanup-owned-channels!` への接続
- [x] [`ulisp/lib/ulisp/concurrency/channel.sld`](../../../ulisp/lib/ulisp/concurrency/channel.sld):
  - 新規 API（`channel-owner`, `channel-transfer-ownership!`, `channel-transfer!`, `channel-disown!`, `channel-share!`, `task-cleanup-owned-channels!`）のエクスポート追加
- [x] [`tests/concurrency/test_channel.scm`](../../../tests/concurrency/test_channel.scm):
  - Group 15: チャネル所有権移転、共有化（disown）、正常終了時 Graceful Drain、クラッシュ時 Poisoning の検証テスト追加

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/752-define-channel-ownership-and-crash-poisoning-semantics`

### Step 1: `<channel>` レコードへの `owner-box` 追加
```scheme
(define-record-type <channel>
  (%make-channel message-queue recv-wait-queue send-wait-queue
                 capacity current-count closed-box
                 sent-count-box received-count-box
                 backpressure-count-box handoff-count-box
                 ring-buffer ring-head-box ring-tail-box ring-mask
                 spsc? owner-box)
  channel?
  ...
  (owner-box              %channel-owner-box))
```

### Step 2: 所有権操作 API の実装
- `(channel-owner ch)`: `(atomic-ref (%channel-owner-box ch))`
- `(channel-transfer-ownership! ch target-task)`:
  1. 現在の owner を取得。
  2. 旧 owner の `owned-channels-box` から `ch` を除去。
  3. `target-task` の `owned-channels-box` に `ch` を登録。
  4. `(%channel-owner-box ch)` を `target-task` に更新。
- `(channel-disown! ch)` / `(channel-share! ch)`:
  1. 旧 owner から登録解除。
  2. `(%channel-owner-box ch)` を `#f` に更新。

### Step 3: タスク終了時クリーンアップの分離 (`task-cleanup-owned-channels!`)
```scheme
(define task-cleanup-owned-channels!
  (case-lambda
    ((t) (task-cleanup-owned-channels! t 'killed #f))
    ((t reason) (task-cleanup-owned-channels! t reason #f))
    ((t reason wake-hook)
     (let ((chs (atomic-swap! (%task-owned-channels-box t) '())))
       (let loop ((xs chs))
         (if (null? xs)
             #t
             (let ((ch (car xs)))
               ;; Clear owner reference so it doesn't point to terminated task
               (atomic-set! (%channel-owner-box ch) #f)
               (if (eq? reason 'normal)
                   ;; Normal termination: Graceful Close allowing consumers to drain buffer!
                   (channel-close! ch)
                   ;; Abnormal crash: Immediate Poisoning preventing deadlocks!
                   (channel-poison! ch reason wake-hook))
               (loop (cdr xs)))))))))
```

### Step 4: `links.scm` の更新
`task-handle-termination!`（`links.scm`）にて：
```scheme
;; Step 1: Clean up owned channels (Graceful close on 'normal, Poison on abnormal crash)
(task-cleanup-owned-channels! task safe-reason wake-hook)
```
※ 後方互換性のため、`task-poison-owned-channels!` は `task-cleanup-owned-channels!` のエイリアスまたは委譲とする。

### Step 5: ユニットテストの作成
`tests/concurrency/test_channel.scm` に Group 14 を追加：
- Case 1: 送信タスクがバッファにメッセージを残して正常終了（`normal`）した場合、チャネルは `closed` となり、受信タスクが残存メッセージをすべてドレインできること。
- Case 2: 送信タスクがパニック・異常クラッシュした場合、チャネルが即座に `poisoned` となり待機タスクが起床すること。
- Case 3: タスク A が生成したチャネルをタスク B に `channel-transfer-ownership!` した後、タスク A がクラッシュしてもチャネルは破壊されずタスク B が継続使用できること。
- Case 4: `channel-disown!` で独立共有化されたチャネルは、生成元タスクがクラッシュしても破壊されないこと。
- Case 5: CWE-843 型検査ガード。

### Step 6: 全体品質ゲートの実行
- `make -C ulisp test_channel` PASS
- `make -C ulisp test_links_monitors` PASS
- `make -C ulisp test_concurrency_ci` PASS
- `make -C ulisp test` PASS
- `make verify_quality` PASS

---

## 7. 完了条件 / Success Criteria (DoD)

- [ ] **所有権移転および独立化 API の実装**:
  - `channel-owner`, `channel-transfer-ownership!`, `channel-disown!`, `channel-share!` が正常に機能すること。
- [ ] **正常終了時の Graceful Drain の確立**:
  - 送信元タスクが `normal` で終了してもチャネルが毒化されず、バッファ内の残存メッセージを受信側が正常に全件ドレインできること。
- [ ] **異常終了時の Crash Poisoning の堅持**:
  - 送信元タスクがパニック・異常終了した際には、直ちにチャネルが毒化され、受信側・送信側の永久ブロック（デッドロック / CWE-833）が確実に防止されること。
- [ ] **所有権移転済みチャネルの保護**:
  - 所有権が他タスクに移転されたチャネル、または `disown` された共有チャネルは、生成元タスクの終了・クラッシュによって道連れ破壊されないこと。
- [ ] **テストスイートの拡充と完全合格**:
  - `tests/concurrency/test_channel.scm` に Group 14 が追加され、全テストが PASS すること。
  - `make -C ulisp test_concurrency_ci` が 100% PASS すること。
  - `make -C ulisp test`（Nanopass 38パス、セルフホスティング bit-for-bit）が 100% PASS すること。
  - `make verify_quality`（2,766+ テスト、静的解析）が 100% PASS すること。
