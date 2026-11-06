---
ID: 741
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] タスク正常終了時のクリーンアップ・DOWN通知および登録解除の実行 (ID: 741)

## 1. 概要 / Summary
タスクが正常に実行を終了した（境界が `(cons 'ok <value>)` を返した）際、タスク終了ライフサイクル処理 `task-handle-termination!`（または `task-exit! 'normal`）が呼び出されない。
これにより以下の重大な問題が発生している：
1. **監視元への通知欠落**: 監視元（`task-monitor`）に `DOWN (normal)` シグナルが届かず、タスク完了を待機する親プロセスや Supervisor がタイムアウトまでブロックまたは無限停止する。
2. **リソース・メモリリーク**: プロセス名レジストリ（`registry`）、グローバルタスク表（`task-table`）、および Link リストからタスクが登録解除されず、終了したタスクコンテキストがメモリ上に永久残存する (CWE-400 / Memory Leak)。
3. **Supervisor 再起動不全**: Supervisor の管理下にある `permanent` 再起動戦略の子タスクが、正常終了時に再起動されず放置される（Erlang/OTP 仕様違反）。

### 再現手順 / Steps to Reproduce
1. 通常の関数 `(lambda () 42)` を実行するタスクコンテキスト `target` を作成し、監視タスク `observer` から `task-monitor` で監視する。
2. スケジューラ上でタスクを実行し、正常に `(cons 'ok 42)` で終了させる。
3. `observer` の通知チャネルに `DOWN (normal)` メッセージが配信されない。
4. `task-table-lookup` で当該 TID を検索すると、依然としてタスクが登録されたまま残存している。
5. Supervisor 配下の `permanent` 子プロセスが正常終了した際、`DOWN` が届かず再起動ループがトリガーされない。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / QEMU AArch64
- 対象ファイル:
  - [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
  - [`ulisp/runtime/concurrency/panic.scm`](../../ulisp/runtime/concurrency/panic.scm)
  - [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm)
  - [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm)
  - [`tests/concurrency/test_links_monitors.scm`](../../tests/concurrency/test_links_monitors.scm)
  - [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm) (`scheduler-execute-task!` での正常完了判定と `task-exit! 'normal` 呼び出し)
- [ ] [`ulisp/runtime/concurrency/panic.scm`](../../ulisp/runtime/concurrency/panic.scm) (`with-synapse-task-boundary` における正常リターン時のクリーンアップ連携)
- [ ] [`ulisp/runtime/concurrency/links.scm`](../../ulisp/runtime/concurrency/links.scm) (`task-handle-termination!` での `'normal` 終了理由の正常処理・リンク非道連れ保証)
- [ ] [`ulisp/runtime/concurrency/supervisor.scm`](../../ulisp/runtime/concurrency/supervisor.scm) (`DOWN (normal)` 受信時の `permanent` 子タスク再起動検証)
- [ ] [`tests/concurrency/test_links_monitors.scm`](../../tests/concurrency/test_links_monitors.scm) (正常終了時の `DOWN (normal)` 受信結合テスト)
- [ ] [`tests/concurrency/test_supervisor.scm`](../../tests/concurrency/test_supervisor.scm) (正常終了した `permanent` 子タスクの自動再起動テスト)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **スケジューラ側の完了処理バイパス (`scheduler.scm`)**:
   `scheduler-execute-task!` において、タスクの `task-next-run`（サンク手続き、または完了したコルーチン）が `with-synapse-task-boundary` から `(cons 'ok <result>)` を返した際、単にその戻り値を返しているだけで `task-state` を `'terminated` に更新せず、`task-exit! ctx 'normal` を呼び出していない。
2. **例外境界と終了処理の非対称性 (`panic.scm`)**:
   異常終了時（例外発生時）は `guard` 節から `synapse-cleanup-task-resources!` -> `task-handle-termination!` が自動実行されるのに対し、正常復帰パス（`(cons 'ok res)`）では何もクリーンアップが走らない構造になっていた。
3. **コルーチン中断（yield）と完了の区別不足**:
   コルーチンの `context-resume!` は途中で `yield` して `(ok . <val>)` を返す場合がある。コルーチンが完全に終了した（`coroutine-terminated? == #t`）時のみ正常終了処理を通す制御ロジックが必要である。

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE)
- **CWE-400: Uncontrolled Resource Consumption (Memory Leak)**:
  タスクが正常終了するたびに、タスクコンテキスト、TID エントリ、リンク/モニター構造体がグローバルタスク表（`task-table`）やレジストリに残存し、長時間稼働時にプロセスが OOM (Out Of Memory) クラッシュを引き起こす。
- **CWE-662: Improper Synchronization (State Inconsistency)**:
  実際には処理を完了したタスクが内部状態として `'running` のまま残り、Supervisor や親プロセスが `DOWN` 通知を受け取れず無限待機・デッドロックに陥る。
- **可用性の喪失 (Permanent Worker Stoppage)**:
  常駐すべき重要なワーカー（`permanent`）が何らかの理由で正常リターンした場合、Supervisor に検知されず再起動されないため、サービスの主要機能が停止する。

---

## 5. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 各タスク処理の末尾で、ユーザコード側から明示的に `(task-exit! 'normal)` を呼び出す。
* **恒久対策 (Permanent Fix)**:
  1. `scheduler-execute-task!` において、タスク（thunk、完了したコルーチン、完了した予算付きタスク）が境界から `ok` を返した際に、自動的に `(task-exit! ctx 'normal)` を実行する。
  2. `with-synapse-task-boundary` に `auto-exit-normal?` オプション（または境界直後のクリーンアップ統合）を整備し、単体呼び出し時にも安全に正常終了ライフサイクルを完結できるようにする。
  3. 正常終了理由 `'normal` による `DOWN` メッセージ送出、タスク表抹消、レジストリ解除、および `permanent` 再起動の統合テストを整備する。

---

## 6. 実装方針 / Implementation Plan
Target Branch: `fix/741-handle-normal-task-termination-and-cleanup`

### Step 1: `ulisp/runtime/concurrency/scheduler.scm` の正常終了処理統合
`scheduler-execute-task!` において、各タスク実行パスの正常リターン時に `task-exit! ctx 'normal` を呼び出す：
```scheme
(let ((nxt (task-next-run ctx)))
  (cond
    ;; 1. コルーチン型タスク:
    ((coroutine-context? nxt)
     (if (not (coroutine-terminated? nxt))
         (let ((res (with-synapse-task-boundary ctx
                      (lambda () (context-resume! nxt)))))
           (cond
             ((and (pair? res) (eq? (car res) 'panic))
              (let ((stk (coroutine-stack nxt)))
                (if (and (task-stack? stk) (not (task-stack-freed? stk)))
                    (%context-raw-u64-set! (task-stack-top stk) -24 3)
                    #f))
              res)
             ((coroutine-terminated? nxt)
              ;; コルーチンが完全に終了した場合のみ normal 終了処理を通す
              (task-exit! ctx 'normal)
              res)
             (else
              ;; 中断 (suspended) の場合は終了処理を呼ばずに値を返す
              res)))
         #f))

    ;; 2. 通常の thunk 手続き:
    ((and (not (vector? nxt)) (procedure? nxt))
     (let ((res (with-synapse-task-boundary ctx nxt)))
       (if (and (pair? res) (eq? (car res) 'ok))
           (begin
             (task-exit! ctx 'normal)
             res)
           res)))

    ;; 3. 予算付きタスク (%is-budgeted-task?):
    ((%is-budgeted-task? nxt)
     (let ((res (with-synapse-task-boundary ctx
                  (lambda () (budgeted-task-execute! nxt)))))
       (if (and (pair? res) (eq? (car res) 'ok) (%budgeted-task-finished? nxt))
           (begin
             (task-exit! ctx 'normal)
             res)
           res)))

    (else
     (task-exit! ctx 'normal)
     (cons 'ok #t))))
```

### Step 2: `ulisp/runtime/concurrency/links.scm` の整合性確認
`task-handle-termination!` において：
- `safe-reason` が `'normal` の場合、リンク先タスク（`linked`）を殺さず（道連れにせず）、リンク関係のみを安全に切り離すことの既存実装を再確認・保護。
- モニター先へ送信される `DOWN` メッセージの理由が `'normal` であることを確認。
- `task-table-unregister!` およびレジストリ登録抹消が確実に実行されることを確認。

### Step 3: `ulisp/runtime/concurrency/supervisor.scm` の `permanent` 子タスク再起動
Supervisor の子タスク監視ハンドラにおいて、`rtype == 'permanent` の子が `DOWN (normal)` を受信した際に、再起動スケジュールが正しくトリガーされることを確認。

### Step 4: 結合テストの追加・検証
1. `tests/concurrency/test_links_monitors.scm`:
   - スケジューラ上で正常終了するタスク（thunk およびコルーチン）を実行し、監視元に `DOWN (normal)` が届くこと、およびタスク表から自動登録抹消されることを検証。
2. `tests/concurrency/test_supervisor.scm`:
   - `permanent` 戦略の子タスクが正常終了（`(lambda () 42)`）した際にも、Supervisor によって自動的に再起動されることを検証。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] 正常終了したタスク（thunk / 完了コルーチン）に対して `task-handle-termination! task 'normal` が自動的に実行されること
- [x] 監視元タスクに対して `DOWN (normal)` メッセージが確実に配信されること
- [x] 正常終了後にグローバルタスク表（`task-table`）およびプロセスレジストリから対象タスクが自動登録抹消され、メモリリークが発生しないこと
- [x] 正常終了時にリンクされたタスクが道連れ終了せず、安全に生存し続けること
- [x] Supervisor 配下の `permanent` 子タスクが正常終了時にも再起動されること
- [x] コルーチンの一時中断（`yield` / suspended）時には誤って終了処理が走らないこと
- [x] `make -C ulisp test_links_monitors test_supervisor test_scheduler test_let_it_crash lint_sexpr` がすべて PASS すること
