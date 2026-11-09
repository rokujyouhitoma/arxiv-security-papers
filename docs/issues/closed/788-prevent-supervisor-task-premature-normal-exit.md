---
ID: 788
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] Supervisor タスクのメールボックス処理完了に伴う誤った正常終了 (task-exit!) の防止 (ID: 788)

## 1. 概要 / Summary
Synapse の Supervisor タスクが、受信メールボックス内のメッセージ（DOWN シグナル等）を1回処理し終えるたびに、スケジューラによって `(task-exit! 'normal)` が実行され誤って終了状態（`terminated`）に遷移する不具合を修正する。

Supervisor のタスクはゼロ引数の手続き（thunk）として登録されているため、スケジューラの thunk 実行パスにおいて処理が完了すると無条件に `task-exit! 'normal` が呼ばれる。その結果、上位の監視者（親 Supervisor 等）へ不要な DOWN (normal) が配信され、タスク登録やリンクが解除される。次の障害で下位から DOWN が届いた際にディスパッチフックが再度 `ready` に戻して再実行するが、入れ子の Supervisor では親側が「子 Supervisor が終了した」と判断して再起動を誤発動させる。

### 再現手順 / Steps to Reproduce
1. 親 Supervisor の配下に子 Supervisor（ツリー構造の監視ツリー）を配置して起動する。
2. 子 Supervisor 配下の Worker が正常終了または DOWN シグナルを送信する。
3. 子 Supervisor のタスクがメールボックスを処理して正常リターンする。
4. スケジューラが子 Supervisor のタスクに対して `(task-exit! ctx 'normal)` を実行する。
5. 親 Supervisor に子 Supervisor の `DOWN (normal)` が届き、親 Supervisor が「子 Supervisor が終了した」と誤認して子 Supervisor を勝手に再起動する。
6. 子 Supervisor のタスク TID が変わり、リンク・レジストリ登録・状態テーブルとの整合性が破壊される。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- Target Files:
  - `ulisp/runtime/concurrency/channel.scm` (`<task-context>` 定義 & 常駐アクセサ)
  - `ulisp/lib/ulisp/concurrency/channel.sld` (シンボル export)
  - `ulisp/runtime/concurrency/scheduler.scm` (`scheduler-execute-task!` の thunk 完了パス)
  - `ulisp/runtime/concurrency/supervisor.scm` (`make-supervisor`, `supervisor-stop!`)
  - `tests/concurrency/test_supervisor.scm` (階層監視ツリーの結合テスト)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [channel.scm](../../ulisp/runtime/concurrency/channel.scm) — `<task-context>` への `resident-box` スロット追加と `task-resident?` / `task-resident-set!` API 実装
- [x] [channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld) — `task-resident?`, `task-resident-set!` の export
- [x] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) — thunk 実行後の `task-resident?` ガードと `waiting` 状態遷移
- [x] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm) — `sup-task` への常駐フラグ付与と停止時のクリーンアップ
- [x] [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm) — 入れ子 Supervisor（親-子-孫）における正常終了誤検知抑止テスト追加

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
### メカニズム詳細
1. **thunk タスク実行完了時の無条件 exit**:
   - `scheduler.scm` の `scheduler-execute-task!`（行 419-425）:
     ```scheme
     ;; Thunk: zero-argument procedure (Issue #741)
     ((and (not (vector? nxt)) (procedure? nxt))
      (let ((res (with-synapse-task-boundary ctx nxt)))
        (if (and (pair? res) (eq? (car res) 'ok))
            (begin
              (task-exit! ctx 'normal)
              res)
            res)))
     ```
   - 一過性のタスク（クロージャ）を実行し終えた際、リソース解放のために #741 で導入された `task-exit! 'normal` が無条件に実行される。
2. **Supervisor タスクのアクター的性質との不一致**:
   - `supervisor.scm` の `make-supervisor` では、メールボックスの DOWN シグナルをポーリングするループ手続きを `task-next-run` に登録している。
   - Supervisor タスクは「1回のポーリング完了＝タスク消滅」ではなく、**次のメッセージが届くまで待機する常駐型アクター（Persistent Actor）** である。
   - にもかかわらず thunk として実行されるため、メールボックスが空になるたびに `task-exit! 'normal` が走り、タスク状態が `terminated` に遷移してしまう。
3. **リンク切断・監視シグナル誤爆・二重起動**:
   - `task-exit!` が走ると、自身を監視している親 Supervisor やリンク先タスクに `DOWN (normal)` / `EXIT (normal)` が送信され、グローバルタスク表や名前レジストリから登録抹消される。
   - 子 Supervisor は生きて動作し続けるべきなのに、親 Supervisor からは「終了した」と認識され、Supervisor ツリー全体で不要な再起動や TID のズレが発生する。

---

## 4. セキュリティ・整合性設計 (Security & Integrity Architecture)
### 脅威分析
- **CWE-400 (Uncontrolled Resource Consumption / Crash-Loop)**: 不要な再起動が連鎖して再起動頻度上限（`max-restarts`）に達し、システム全体がフェイルセーフ停止（Escalation Panic）に追い込まれる。
- **CWE-672 (Operation on Resource after Expiration or Release)**: `task-exit!` で解放されたタスクコンテキストが、後続の DOWN 通知によって無理やり再実行されることによるゾンビタスクの発生。
- **CWE-843 (Type Confusion / Lifecycle Confusion)**: 常駐型アクターが一過性バッチタスクと混同されることによるライフサイクル状態不整合。

### 防御策 (Mitigation)
- **明示的な常駐タスクフラグ（`task-resident?`）**:
  - タスクコンテキストに常駐属性（`resident-box`）を導入。
  - スケジューラは、常駐タスクが正常リターンした場合には `task-exit! 'normal` を呼び出さず、`task-state` を `waiting` に更新して待機状態を維持する。
- **ライフサイクルの分離**:
  - 常駐タスクの終了は、明示的な停止命令（`supervisor-stop!` による `task-resident-set! #f` とクリーンアップ）または致命的 panic のみによって行われるように厳格化する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/788-supervisor-task-persistent-resident`

### Step 1: `<task-context>` に常駐タスク属性を追加
- [channel.scm](../../ulisp/runtime/concurrency/channel.scm):
  - `<task-context>` レコードに `resident-box` フィールドを追加。
  - `%task-resident-box` アクセサを定義。
  - 以下の公開 API を実装:
    ```scheme
    (define (task-resident? task)
      (if (not (task-context? task))
          #f
          (atomic-ref (%task-resident-box task))))

    (define (task-resident-set! task resident?)
      (if (not (task-context? task))
          (error "task-resident-set!: expected <task-context> (CWE-843)" task)
          (begin
            (atomic-set! (%task-resident-box task) (if resident? #t #f))
            resident?)))
    ```
  - デフォルト値は `#f`（一過性タスク）。
- [channel.sld](../../ulisp/lib/ulisp/concurrency/channel.sld):
  - `task-resident?`, `task-resident-set!` を export リストに追加。

### Step 2: スケジューラの thunk 完了パスの改修
- [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm):
  - `scheduler-execute-task!` の thunk 実行ブロック（行 419-425）を以下のように更新:
    ```scheme
    ;; Thunk: zero-argument procedure (Issue #741, #788)
    ((and (not (vector? nxt)) (procedure? nxt))
     (let ((res (with-synapse-task-boundary ctx nxt)))
       (if (and (pair? res) (eq? (car res) 'ok))
           (if (task-resident? ctx)
               ;; Resident actor task: do NOT exit! Transition to idle/waiting
               (begin
                 (if (not (eq? (task-state ctx) 'terminated))
                     (task-state-set! ctx 'waiting))
                 res)
               (begin
                 (task-exit! ctx 'normal)
                 res))
           res)))
    ```

### Step 3: Supervisor の `sup-task` への常駐フラグ設定
- [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm):
  - `make-supervisor` において、`sup-task` 生成直後に `(task-resident-set! sup-task #t)` を実行。
  - `supervisor-stop!` において、停止シーケンスで `(task-resident-set! sup-task #f)` をセットした上で正規の終了処理を実行。

### Step 4: 階層 Supervision Tree の結合テスト追加
- [test_supervisor.scm](../../tests/concurrency/test_supervisor.scm):
  - `Group 15: Nested Supervision Tree & Persistent Supervisor Tasks (Issue #788)` を新設。
  - 親 Supervisor の配下に子 Supervisor（Supervisor as Child）を登録。
  - 子 Supervisor 配下の Worker が正常終了および異常終了した際：
    1. 子 Supervisor が DOWN を処理して Worker を再起動すること。
    2. 子 Supervisor 自身のタスク状態が `waiting` に留まり、親 Supervisor に誤って `DOWN (normal)` が送信されないこと。
    3. 親 Supervisor が子 Supervisor を不要に再起動せず、子 Supervisor の TID が不変であることを検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] Supervisor タスクがメールボックス処理完了後も `terminated` に遷移せず `waiting` 状態を維持すること。
- [x] 上位の監視者（親 Supervisor 等）へ不要な `DOWN (normal)` 通知が送出されないこと。
- [x] 階層 Supervision Tree（入れ子の Supervisor）において、配下の Worker が死活を繰り返しても子 Supervisor が安定して稼働し続けること。
- [x] `supervisor-stop!` 実行時には確実に `terminated` 状態となりリソースが解放されること。
- [x] `make test_supervisor` および並行性テストスイートが 100% PASS すること。

---

## 7. 検証結果 / Verification Results
- `make test_supervisor`: 139 passed, 0 failed (Group 15 新設: 15.1〜15.4 全パス)
- `make test_scheduler`: 167 passed, 0 failed
- `make test_multithread_scheduler`: 55 passed, 0 failed
- `make test_context_switch`: 89 passed, 0 failed
- `make test_let_it_crash`: 113 passed, 0 failed
- `make py_compile`: 0 errors / 警告なし
