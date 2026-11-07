---
ID: 751
種別: Bug
優先度: High
ステータス: Closed
関連 Issue: #727, #743, #750, #726
---

# [BUG/SEC] Supervisor 受信ループにおける非 DOWN シグナル (EXIT, io_complete 等) の破棄防止 (ID: 751)

## 1. 概要 / Summary

Synapse 並行性ランタイムにおける Erlang/OTP 互換スーパーバイザーツリー実装（[`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)）では、Supervisor 自体が `<task-context>` を内包する独立アクタータスクとして動作し、自タスクのメールボックスから子タスクのクラッシュ・終了通知を吸い上げる（`supervisor-poll-down-signals!`、Issue #743）。

しかし、現在の `supervisor-poll-down-signals!`（L593-599）の実装では、メールボックスからデキューしたメッセージのうち `(DOWN ...)` 形式以外のメッセージ（`EXIT` シグナル、`io_complete` 通知、チャネル汚染通知、RPC 制御メッセージ等）が**条件分岐の else 節で一切処理されず無条件に破棄（Silent Discard）** されている。

この結果、以下の重大な脆弱性・不具合が生じている：
1. **Link された子タスクの `EXIT` シグナル消失 (CWE-703 / CWE-400)**:
   Supervisor が子タスクや親 Supervisor と双方向リンク（`task-link!`）されている場合、または `trap-exit` モードで動作している場合、子タスクがクラッシュした際に届く `(EXIT <from-tid> <reason>)` シグナルが捨てられ、再起動がトリガーされずゾンビタスクが残留する。
2. **Supervisor 宛て非同期 I/O・制御通知の消失 (CWE-400)**:
   Supervisor がログ書き込みや監視用 `io_uring` 非同期 I/O を実行した際の `(cons 'io_complete ...)` や、外部からの状態照会メッセージがメールボックス通過時に破棄される。

本 Issue では、`supervisor-poll-down-signals!` を刷新し、**子タスクからの `EXIT` シグナルを自動検知して再起動へ連動** させるとともに、その他の有効なメッセージを **保留キュー（`preserved-inbox`）に安全に退避** し、登録された **カスタムメッセージハンドラへ適切にディスパッチ** する堅牢なシグナル保持・ルーティング機構を確立する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Denial of Service (DoS)** / Zombie Leak | **CWE-703**: Improper Check or Handling of Exceptional Conditions | High | Supervisor に `EXIT` シグナルで子タスククラッシュが通知された際、`DOWN` ではないため握りつぶされ再起動が実行されない。システムの一部が機能停止したまま放置され、クラッシュ障害から自己治癒できない。 |
| **Integrity Violation (整合性侵害)** | **CWE-400**: Uncontrolled Resource Consumption / Lost Notifications | High | 非同期 I/O 完了通知 `(io_complete ...)` やチャネル poison 通知がポーリング時に破棄され、Supervisor 内部の I/O ハンドラが未完了のまま永久ハング（リソースリーク）する。 |
| **Repudiation (否認・追跡困難)** | **CWE-778**: Insufficient Logging / Missing Event Delivery | Medium | 外部プロセスからの管理コマンドや監査通知が黙ってドロップされ、Supervisor のログや状態追跡が破綻する。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が存在しているか
[`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm) L593-599：
```scheme
(let ((msg (task-take-handoff! sup-task)))
  (if (and (pair? msg) (eq? (car msg) 'DOWN) (>= (length msg) 5))
      (let* ((target-tid (list-ref msg 3))
             (reason (list-ref msg 4))
             (h-res (supervisor-handle-child-down! sup target-tid reason)))
        (drain-loop h-res))
      (drain-loop res))) ; <- ここで DOWN 以外のメッセージが完全に破棄されている！
```
Issue #727 および #743 において Supervisor をタスク化して Monitor の `DOWN` シグナルを受け取る機構を構築した際、`DOWN` 以外のシグナル（`EXIT` 等）の取り扱い方針が未定であったため、else 節で単にループを継続する仮コードが残存していた。

---

## 4. 恒久対策アーキテクチャ設計 (Signal Preservation & Intelligent Routing)

### 4.1 シグナル分類とルーティング方針
Supervisor が受信したメッセージを以下の優先順位でルーティングする：

1. **`DOWN` シグナル (`(DOWN <ref> <subject> <target-tid> <reason>)`)**:
   - 既存通り `supervisor-handle-child-down!` を呼び出し、該当する子タスクの再起動戦略（`one_for_one`, `one_for_all`, `rest_for_one`）を実行。
2. **`EXIT` シグナル (`(EXIT <from-tid> <reason>)`)**:
   - `from-tid` が現在 Supervisor が管理している子タスク（`%supervisor-child-by-tid`）である場合：
     `DOWN` と同様に子タスクの異常終了として解釈し、`supervisor-handle-child-down!` を呼び出す。
   - `from-tid` が子タスクでない場合（外部タスクや親 Supervisor からのリンクシグナル）：
     カスタムハンドラへディスパッチ、または `preserved-inbox` に保持。
3. **カスタムメッセージハンドラ (`supervisor-message-handler`)**:
   - Supervisor インスタンスに登録されたハンドラプロシージャ `(lambda (sup msg) ...)` があれば呼び出す。
   - ハンドラが `#t`（処理済み）を返した場合はそのまま消費。
4. **保留キューへの安全退避 (`preserved-inbox`)**:
   - ハンドラで処理されなかった、または未登録のすべての非 DOWN/EXIT メッセージ（`io_complete`、未認識シグナル等）を `<supervisor-context>` 内の `preserved-inbox-box`（CAS ロックフリーリスト）に退避・保持。
   - 外部または呼び出し元は `(supervisor-preserved-messages sup)` や `(supervisor-take-preserved-message! sup)` で取り出して処理可能。

### 4.2 `<supervisor-context>` レコードの拡張
`<supervisor-context>` に以下の2つのアトミックボックスを追加：
- `preserved-inbox-box`: 未処理メッセージを FIFO 順で保持する `<atomic-box>`。
- `message-handler-box`: カスタムメッセージハンドラを保持する `<atomic-box>`。

### 4.3 提供 API 一覧
- `(supervisor-poll-down-signals! sup)`: 既存のシグナル処理ループ（非 DOWN シグナルの保持・ディスパッチ対応版）
- `(supervisor-preserved-messages sup)`: 退避された未処理メッセージの一覧を取得
- `(supervisor-take-preserved-message! sup)`: 退避キューから最古のメッセージを1件デキュー
- `(supervisor-clear-preserved-messages! sup)`: 退避メッセージリストをクリア
- `(supervisor-set-message-handler! sup handler)`: カスタムメッセージハンドラを設定

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm):
  - `<supervisor-context>` 定義およびアクセサ（`preserved-inbox-box`, `message-handler-box`）の追加
  - `make-supervisor` 初期化処理の更新
  - `supervisor-poll-down-signals!` のルーティング・保留ロジック刷新
  - `supervisor-preserved-messages`, `supervisor-take-preserved-message!`, `supervisor-clear-preserved-messages!`, `supervisor-set-message-handler!` の実装
- [x] [`ulisp/lib/ulisp/concurrency/supervisor.sld`](../../ulisp/lib/ulisp/concurrency/supervisor.sld):
  - 新規 API のエクスポート追加
- [x] [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm):
  - Group 14: 非 DOWN シグナル保持・EXIT 自動再起動・カスタムハンドラディスパッチ検証テストの追加

---

## 6. 実装方針 / Implementation Plan

Target Branch: `fix/751-preserve-non-down-signals-in-supervisor-inbox`

### Step 1: `<supervisor-context>` への保留キューとハンドラフィールドの追加
`supervisor.scm` にてレコード定義を拡張：
```scheme
(define-record-type <supervisor-context>
  (%make-supervisor-context spec sup-task children-box restart-history-box parent-sup
                            state-box scheduler-box processing-box
                            preserved-inbox-box message-handler-box)
  supervisor-context?
  ...
  (preserved-inbox-box  %supervisor-preserved-inbox-box)
  (message-handler-box  %supervisor-message-handler-box))
```

### Step 2: 保留メッセージ操作 API の実装
- `(supervisor-preserved-messages sup)`
- `(supervisor-take-preserved-message! sup)`
- `(supervisor-clear-preserved-messages! sup)`
- `(supervisor-set-message-handler! sup handler)`

### Step 3: `supervisor-poll-down-signals!` の刷新
1. `(task-take-handoff! sup-task)` でメッセージを取得。
2. `(DOWN ...)`: `supervisor-handle-child-down!` を実行。
3. `(EXIT from-tid reason)`:
   - `(%supervisor-lookup-child-by-tid sup from-tid)` が存在すれば、`supervisor-handle-child-down!` を実行。
   - 存在しなければ、メッセージハンドラまたは `preserved-inbox-box` へ転送。
4. その他のメッセージ（`io_complete` 等）：
   - `message-handler` が登録されていれば呼び出し。
   - 未処理なら `preserved-inbox-box` の末尾に追加（または逆順 cons 後に reverse）。

### Step 4: ユニットテストの作成
`tests/concurrency/test_supervisor.scm` に Group 14 を追加：
- Case 1: `DOWN` と `io_complete` が混在して到着した場合、`DOWN` で子タスクが再起動され、`io_complete` が `preserved-inbox` に無傷で保持されること。
- Case 2: 子タスクから `(EXIT <child-tid> 'crash)` が届いた場合、Supervisor が子タスククラッシュと認識して自動再起動すること。
- Case 3: カスタムハンドラを設定した際、非 DOWN メッセージが正常にハンドラへ渡されること。
- Case 4: 複数メッセージの混在順序（FIFO）が保持されること。

### Step 5: 全体品質ゲートの実行
- `make -C ulisp test_supervisor` PASS
- `make -C ulisp test_concurrency_ci` PASS
- `make -C ulisp test` PASS
- `make verify_quality` PASS

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **非 DOWN シグナルの完全保護**:
  - `supervisor-poll-down-signals!` 実行時に、`EXIT`, `io_complete`, その他カスタムメッセージが 1 件も破棄されず安全に保持または処理されること。
- [x] **子タスク `EXIT` シグナルからの自動再起動**:
  - 子タスクの Task ID を持つ `(EXIT ...)` シグナルを受信した際、Supervisor が子タスクダウンとして検知し再起動を実行すること。
- [x] **保留メッセージ操作 API の提供**:
  - `supervisor-preserved-messages`, `supervisor-take-preserved-message!`, `supervisor-set-message-handler!` が正しく動作すること。
- [x] **既存動作の完全維持**:
  - 既存の `test_supervisor.scm`（Group 1〜13）がすべて 100% PASS すること。
- [x] **テストスイートの拡充と完全合格**:
  - `tests/concurrency/test_supervisor.scm` に Group 14 が追加され、全グループが PASS すること。
  - `make -C ulisp test_concurrency_ci` が PASS すること。
  - `make -C ulisp test`（Nanopass 38パス、セルフホスティング bit-for-bit）が 100% PASS すること。
  - `make verify_quality`（2,766+ テスト、静的解析）が 100% PASS すること。
