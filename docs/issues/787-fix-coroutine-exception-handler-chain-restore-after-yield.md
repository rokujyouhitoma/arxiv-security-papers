---
ID: 787
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] コルーチンが yield したあとの例外ハンドラ連鎖復元不具合の修正 (ID: 787)

## 1. 概要 / Summary
Synapse 並行性ランタイムにおいて、コルーチンが `yield` した後の再開（`resume`）時に例外ハンドラ連鎖（`ulisp_handler_chain`）が不正に復元される不具合を修正する。

コルーチンが自身でハンドラを持たない場合、初回の再開時に worker スタック上に作成された境界フレームのアドレスが `yield` 時にタスクコンテキスト（`[rcx - 32]`）に保存される。2回目以降の再開ではこのアドレスが残存しているためそのまま採用されるが、前回のスタックフレームは既に解放されている。そのため、2回目以降の再開で例外が発生すると解放済みフレームへジャンプ（または他ワーカーにスチールされた場合は別スレッドのスタックへジャンプ）し、スタック破壊やセグメンテーションフォールトを引き起こす。

### 再現手順 / Steps to Reproduce
1. コルーチン型タスクを起動し、一度 `yield` させる。
2. コルーチンを（可能であれば別の worker スレッドで）再開する。
3. 再開後のコルーチン内で例外を発生させる（例: `(car '())`）。
4. 無効化されたスタックフレームまたは別スレッドのスタックへ不正ジャンプし、ランタイムクラッシュまたはメモリ破壊が発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / Synapse Concurrency Runtime
- File: `ulisp/runtime/concurrency/context.s` (`ulisp_fn__pctasm_yield_task_excl`, `ulisp_fn__pctasm_resume_task_excl`)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [context.s](../../ulisp/runtime/concurrency/context.s)
- [ ] [context.scm](../../ulisp/runtime/concurrency/context.scm)
- [ ] [test_context_switch_input.scm](../../ulisp/build/test_context_switch_input.scm)
- [ ] [test_multithread_scheduler_input.scm](../../ulisp/build/test_multithread_scheduler_input.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `ulisp/runtime/concurrency/context.s` の `ulisp_fn__pctasm_yield_task_excl`（行 338-340）にて、中断時に現在の TLS ハンドラ連鎖の先頭 `ulisp_handler_chain[r8]` をそのままタスクの保存領域 `[rcx - 32]` に書き込んでいる。
- コルーチン起動時に worker スタック上に作成された境界の例外ハンドラフレームがチェーンの先頭にある場合、コルーチンがローカルに例外ハンドラを push していなければ、境界フレームのポインタが保存される。
- `ulisp_fn__pctasm_resume_task_excl`（行 289-293）では、`[rdi - 32]` が 0 でない場合にそれをそのまま `ulisp_handler_chain` に書き戻す。
- しかし、worker スタック上の境界フレームは前回の `resume` 呼び出しがリターンした時点で失効しているため、2回目以降の再開ではダングリングポインタとなる。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: コルーチン内部で必ずダミーの例外ハンドラ（`guard` など）を張り、タスク固有のフレームをチェーン先頭に維持させる。
* **恒久対策 (Permanent Fix)**:
  - `yield` 時に、タスク境界フレームより先（worker スタック側）を保存しない（タスクローカルなフレームのみを残す）。
  - または、再開（`resume`）ごとに、現在の worker スタック上に新しく張られた境界フレームの上に、タスクローカルなハンドラフレームをリンクし直す。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/787-coroutine-exception-handler-after-yield`

1. `context.s` において、`yield` 時にタスク自身のハンドラ連鎖のみを分離して保存する、または `resume` 時に現在の worker 境界フレームを末尾としてタスクハンドラ連鎖を再リンクするアセンブリルーチンを実装。
2. コルーチンが 1 回 `yield` した後に再開され、再開後に例外 `(car '())` が発生した場合に安全に現在のタスク境界で捕捉されることを検証するテストを追加。
3. ワークスチールにより別スレッドの worker で再開された場合でも安全に例外ハンドリングが行われる並行テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] コルーチンが複数回 `yield` した後に例外を発生させてもスタック破壊やセグフォが発生しない。
- [ ] 別 worker スレッドによるスチール再開後の例外発生でも安全に境界で捕捉・回復できる。
- [ ] `make test` および並行実行テストスイートが 100% PASS すること。

