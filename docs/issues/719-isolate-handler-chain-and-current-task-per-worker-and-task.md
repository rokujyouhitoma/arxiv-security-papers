---
ID: 719
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] Synapse ハンドラ連鎖 (ulisp_handler_chain) と実行中タスク記録の Worker TLS・タスク単位隔離 (ID: 719)

## 1. 概要 / Summary
現在、例外ハンドラ連鎖 `ulisp_handler_chain` および実行中タスクの記録 `*active-current-task-box*` がプロセス全体で単一のグローバル領域に置かれている。そのため、マルチスレッド Worker 実行時やタスク（コルーチン）切り替え時に別タスクの例外ハンドラやカレントタスク参照が混線・上書きされる問題（項目 A1）を解消し、Worker ごとの TLS およびタスクごとの保存・復元に隔離する。

### 再現手順 / Steps to Reproduce
1. 複数の Worker スレッドまたは複数タスクでそれぞれ `with-exception-handler` / `with-synapse-task-boundary` を設定する。
2. タスク切り替えまたは並列実行中に一方のタスクで `error` / `raise` / `synapse-panic!` を発生させる。
3. グローバルな `ulisp_handler_chain` や `*active-current-task-box*` が他方のタスクによって上書きされており、誤ったハンドラへのジャンプや別タスクのコンテキスト汚染が発生する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/backend/140_backend_x86_64.scm`, `ulisp/backend/160_backend_c.scm`, `ulisp/runtime/concurrency/context.scm`, `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/scheduler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
- [ ] [142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm)
- [ ] [160_backend_c.scm](../../ulisp/backend/160_backend_c.scm)
- [ ] [context.scm](../../ulisp/runtime/concurrency/context.scm)
- [ ] [context.s](../../ulisp/runtime/concurrency/context.s)
- [ ] [channel.scm](../../ulisp/runtime/concurrency/channel.scm)
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp_handler_chain` がシングルスレッド前提の単一グローバルシンボルとして定義されており、Worker スレッド間の分離（TLS）およびタスクコンテキストスイッチ時の退避・復元が行われていない。
- `*active-current-task-box*` もプロセス単一の `atomic-box` であり、Worker ごとの `current-task-box` と連動していない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: シングルスレッドかつタスク切り替えを伴わない逐次実行に限定する。
* **恒久対策 (Permanent Fix)**: `ulisp_handler_chain` と実行中タスク参照を Worker ごとの TLS（または Worker コンテキスト）に移し、タスク切り替え（`swap_context` / スケジューラディスパッチ）のたびに `<task-context>` / TCB ヘッダへ保存・復元する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/719-isolate-handler-chain-and-current-task`

1. `<task-context>` およびマイクロスタック TCB ヘッダにタスク固有の `handler-chain` 保存スロットを追加する。
2. `ulisp_handler_chain` を Worker ごとの TLS に移し、タスク切り替え時（`swap_context` およびスケジューラ境界）に保存・復元する。
3. `*active-current-task-box*` を Worker ごとのカレントタスク記録に統合し、並列 Worker 間で干渉しないようにする。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp_handler_chain` が Worker ごとの TLS およびタスクごとの退避スロットで管理され、タスク切り替え時に保存・復元されること。
- [ ] 実行中タスクの記録（`current-synapse-task`）が Worker ごとに独立して保持されること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

