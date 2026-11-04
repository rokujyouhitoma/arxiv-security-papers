---
ID: 719
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] Synapse ハンドラ連鎖 (ulisp_handler_chain) と実行中タスク記録の Worker TLS・タスク単位隔離 (ID: 719)

## 1. 概要 / Summary
現在、例外ハンドラ連鎖 `ulisp_handler_chain` および実行中タスクの記録 `*active-current-task-box*` がプロセス全体で単一のグローバル領域に置かれている。そのため、マルチスレッド Worker 実行時やタスク（コルーチン）切り替え時に別タスクの例外ハンドラやカレントタスク参照が混線・上書きされる問題（項目 A1）を解消し、Worker ごとの TLS およびタスクごとの保存・復元に隔離する。

### 再現手順 / Steps to Reproduce
1. 複数の Worker スレッドまたは複数タスク（コルーチン）でそれぞれ `with-exception-handler` / `guard` / `with-synapse-task-boundary` を設定する。
2. `context-resume!` / `context-yield!` / `context-switch!` によるタスク切り替え、または複数 OS スレッド Worker による並列実行中に一方のタスクで `error` / `raise` / `synapse-panic!` を発生させる。
3. グローバルな `ulisp_handler_chain` や `*active-current-task-box*` が他方のタスクや別 Worker によって上書きされており、誤ったハンドラへのジャンプや別タスクのコンテキスト汚染が発生する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/backend/140_backend_x86_64.scm`, `ulisp/backend/142_backend_x86_freestanding.scm`, `ulisp/backend/160_backend_c.scm`, `ulisp/runtime/concurrency/context.s`, `ulisp/runtime/concurrency/thread.s`, `ulisp/runtime/concurrency/context.scm`, `ulisp/runtime/concurrency/channel.scm`, `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/scheduler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [140_backend_x86_64.scm](../ulisp/backend/140_backend_x86_64.scm)
- [x] [142_backend_x86_freestanding.scm](../ulisp/backend/142_backend_x86_freestanding.scm)
- [x] [150_backend_aarch64.scm](../ulisp/backend/150_backend_aarch64.scm)
- [x] [160_backend_c.scm](../ulisp/backend/160_backend_c.scm)
- [x] [context.s](../ulisp/runtime/concurrency/context.s)
- [x] [thread.s](../ulisp/runtime/concurrency/thread.s)
- [x] [context.scm](../ulisp/runtime/concurrency/context.scm)
- [x] [channel.scm](../ulisp/runtime/concurrency/channel.scm)
- [x] [panic.scm](../ulisp/runtime/concurrency/panic.scm)
- [x] [scheduler.scm](../ulisp/runtime/concurrency/scheduler.scm)
- [x] [test_context_switch.scm](../tests/concurrency/test_context_switch.scm)
- [x] [test_let_it_crash.scm](../tests/concurrency/test_let_it_crash.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp_handler_chain` が `140_backend_x86_64.scm` (`.quad 0`) および `160_backend_c.scm` (`static void *ulisp_handler_chain`) にてシングルスレッド前提の単一グローバル変数として定義されており、Worker スレッド間の分離（TLS）およびコルーチン／タスクコンテキストスイッチ時（`%asm-resume-task!`, `%asm-yield-task!`, `%asm-switch-task!`）の退避・復元が行われていない。
- `context.s` 内の `ulisp_current_task_top` も単一グローバルスロットになっており、複数 Worker スレッドで同時にコルーチンを実行すると競合する。
- `panic.scm` の `*active-current-task-box*` もプロセス単一の `atomic-box` であり、Worker ごとの TLS スロットおよび `scheduler.scm` の `%worker-current-task-box` と連動していない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: シングルスレッドかつタスク切り替えを伴わない逐次実行に限定する。
* **恒久対策 (Permanent Fix)**:
  1. `ulisp_handler_chain` および `ulisp_current_task_top` を Worker スレッドごとの TLS スロット配列（最大 64 Worker 対応、C バックエンドでは `_Thread_local` / `__thread`）に拡張し、`thread.s` のスレッド生成時に `ulisp_thread_idx_mask` を有効化して各 Worker の独立ヒープ領域 (`r12`) からゼロシステムコールで Worker TLS スロットを解決する。
  2. `<task-stack>` の TCB ヘッダ (`[top - 32]`) および `<task-context>` (`handler-chain-box`) にタスク固有の `ulisp_handler_chain` 保存領域を設け、`%asm-resume-task!`, `%asm-yield-task!`, `%asm-switch-task!` ならびに `with-synapse-task-boundary` の入退場で `ulisp_handler_chain` を保存・復元する。
  3. `panic.scm` のカレントタスク記録 (`current-synapse-task` / `%set-current-synapse-task!`) を Worker TLS スロットごとのベクタ (`*worker-current-task-tls*`) に隔離し、`scheduler.scm` の `%scheduler-run-and-record!` およびコルーチン切り替え時にも連動して保存・復元する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/719-isolate-handler-chain-and-current-task`

1. `ulisp/backend/140_backend_x86_64.scm`, `142_backend_x86_freestanding.scm`, `160_backend_c.scm` において、`ulisp_handler_chain` を Worker TLS 対応（x86-64 では 64 Worker スロット `.zero 512` + `ulisp_thread_idx_mask` による Worker TLS アドレス解決、C99 では `__thread` 指定）に変更する。
2. `ulisp/runtime/concurrency/thread.s` の `%sys-spawn-thread` において `ulisp_thread_idx_mask` を `63` に設定し、Worker スレッド識別プリミティブ `%sys-current-worker-tls-slot` を追加する。
3. `ulisp/runtime/concurrency/context.s` および `context.scm` において、`ulisp_current_task_top` を 64 Worker TLS スロット化し、`%asm-resume-task!`, `%asm-yield-task!`, `%asm-switch-task!`, `ulisp_task_exit_trampoline` で TCB ヘッダ `[top - 32]` へ `ulisp_handler_chain` を自動退避・復元する。また `%asm-get-handler-chain` / `%asm-set-handler-chain!` / `%asm-current-worker-slot` プリミティブを提供する。
4. `ulisp/runtime/concurrency/channel.scm`, `panic.scm`, `scheduler.scm` において、`<task-context>` に `handler-chain-box` を追加し、`current-synapse-task` を Worker TLS ごとに独立保持させるとともに、`%scheduler-run-and-record!` と `with-synapse-task-boundary` でカレントタスクとハンドラ連鎖を保存・復元する。
5. `tests/concurrency/test_context_switch.scm` および `tests/concurrency/test_let_it_crash.scm` にコルーチン切り替え時およびマルチ Worker 時の例外ハンドラ連鎖・カレントタスク隔離テストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp_handler_chain` が Worker ごとの TLS およびタスクごとの退避スロットで管理され、タスク切り替え時に保存・復元されること。
- [x] 実行中タスクの記録（`current-synapse-task`）が Worker ごとおよびタスク切り替えごとに独立して保持されること。
- [x] `make -C ulisp test_context_switch test_exceptions test_let_it_crash test_scheduler test_multithread_scheduler` がすべて PASS すること。
- [x] ドキュメント内に絶対パスが含まれないこと。


