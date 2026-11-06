---
ID: 745
種別: Bug
優先度: High
ステータス: Open (In Progress)
---

# [BUG/SEC] タスク完全停止確認後の安全な Ephemeral Arena リセット (ID: 745)

## 1. 概要 / Summary
タスク終了処理における「タスクが停止したか」の判定ロジック（`reductions <= 0`）が、判定の直前に 0 が代入されているため常に真となってしまう。
その結果、`brutal_kill` や外部強制終了が発生した際、他スレッドでまだ動作中のタスクの Ephemeral Arena が先行してリセット（メモリ解放・再利用）されてしまい、解放済みメモリへのアクセス（Use-After-Free / メモリ破損）を引き起こす危険がある。

### 再現手順 / Steps to Reproduce
1. OS スレッド worker 上で長時間処理を実行中のタスクに対し、別スレッドから `brutal_kill` を発行する。
2. 終了判定で直前に 0 が代入された reductions を評価し、即座に「停止済み」と誤判定される。
3. 稼働中タスクの Arena がリセットされ、メモリ領域が他タスクに再割当される。
4. 元のタスクが実行中のメモリアドレスへアクセスし、SEGV またはヒープ破損が発生する。

### 再現環境 / Environment
- OS / Env: Multi-threaded OS workers (Linux x86-64)
- File: `ulisp/runtime/concurrency/arena.scm`, `ulisp/runtime/concurrency/boundary.scm`, `ulisp/runtime/concurrency/scheduler.scm`
- 関連 Issue: Follow-up of #723, #724

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/runtime/concurrency/arena.scm`](../../ulisp/runtime/concurrency/arena.scm)
- [ ] [`ulisp/runtime/concurrency/boundary.scm`](../../ulisp/runtime/concurrency/boundary.scm)
- [ ] [`ulisp/runtime/concurrency/scheduler.scm`](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [`ulisp/tests/test_let_it_crash.scm`](../../ulisp/tests/test_let_it_crash.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
強制終了処理時に reductions を強制的に 0 に設定する処理と、「実行中か否か」のステート判定が同一のフィールドに依存していた。OS スレッドやコルーチンの実行状態フラグ（`TASK_STATUS_TERMINATED` / 境界を完全に抜けたこと）を確認せずに、reductions カウンタのみで停止を判断していた設計ミスによる。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Arena リセットを遅延させ、GC 実行時まで解放を保留する。
* **恒久対策 (Permanent Fix)**: タスクが境界を完全に脱出（スレッド/コルーチンのフレームが巻き戻され、終了状態がアトミックに確定）したことを確認してから Arena をリセットする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/745-verify-task-stop-before-arena-reset`

1. `ulisp/runtime/concurrency/boundary.scm`:
   - タスク終了時のエピローグにおいて、スタック巻き戻しおよびハンドラ脱出が完了した時点でアトミックに `task-state` を `STOPPED` に遷移させる。
2. `ulisp/runtime/concurrency/arena.scm`:
   - `arena-reset!` の呼び出し条件に `(eq? (task-state t) 'STOPPED)` を必須化。
   - 実行中状態のタスクに対して強制終了が要求された場合は `STOP_REQUESTED` フラグを立てるにとどめ、実際の Arena 解放はタスク自身が境界を脱出するエピローグ処理内、またはスケジューラ回収ループに委ねる。
3. `ulisp/tests/test_let_it_crash.scm`:
   - 強制終了時に動作中タスクの Arena が安全に保護され、完全停止後にのみリセットされることを検証するテストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 動作中のタスクに対して Arena が誤ってリセットされないこと
- [ ] reductions <= 0 に依存した誤判定が排除され、明示的な停止状態（STOPPED）で判定されること
- [ ] Use-After-Free やヒープ破損のリスクが解消されること
- [ ] `ulisp/tests/test_let_it_crash.scm` が PASS すること

