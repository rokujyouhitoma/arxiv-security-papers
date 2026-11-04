---
ID: 723
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] Link 強制終了時の Reduction ゼロ化・Safepoint 脱出と実行停止確認後の安全な資源後始末 (ID: 723)

## 1. 概要 / Summary
現在、Link による連鎖強制終了（項目 B6）ではタスクの状態を `'terminated` に変えるだけで、実行中のタスク自体の計算は止まっていない。また後始末処理（項目 A4）も、タスクの実行が止まったことを確かめずに資源（Arena・Channel）を片付けている。Link 強制終了時には `'terminated` にしたうえで reduction を `0` にして safepoint で即座に抜けさせ、実行停止を確認してから資源を片付ける手順に改修する。

### 再現手順 / Steps to Reproduce
1. 双方向リンクされた2つのタスク A, B を並列実行する。
2. タスク A が異常終了し、`task-handle-termination!` からタスク B の強制終了が呼ばれる。
3. タスク B の状態フラグのみが `'terminated` になるが、タスク B は safepoint で停止せず走り続け、後始末によってリセットされた Arena にアクセスしてしまう。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/links.scm`, `ulisp/runtime/concurrency/preempt.scm`, `ulisp/runtime/concurrency/panic.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [links.scm](../../../ulisp/runtime/concurrency/links.scm)
- [x] [preempt.scm](../../../ulisp/runtime/concurrency/preempt.scm)
- [x] [panic.scm](../../../ulisp/runtime/concurrency/panic.scm)
- [x] [test_links_monitors.scm](../../../tests/concurrency/test_links_monitors.scm)
- [x] [test_preemption.scm](../../../tests/concurrency/test_preemption.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `task-handle-termination!`（`links.scm:187`）が `(task-state-set! task 'terminated)` のみを呼び、`(%task-reductions-set! task 0)` による reduction のゼロ化を行っていなかった。
- `preempt.scm` の `%check-safepoint-impl!` が `<budgeted-task>` のみを対象とし、対象タスクまたは現在のタスクが `'terminated` の場合に reduction を再補充せず即座にタスク境界（`task-escape-continuation`）へ脱出させる処理が欠落していた。
- `synapse-cleanup-task-resources!`（`panic.scm:66`）が対象タスクの状態を `'terminated`・reduction `0` に確定させて実行停止を保証する前に `arena-reset!` を呼んでおり、さらに他ワーカーで実行中だったタスクが safepoint 脱出時に遅延クリーンアップを行う仕組みがなかった。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: タスク側で手動で `(eq? (task-state self) 'terminated)` をポーリングする。
* **恒久対策 (Permanent Fix)**: B6 と A4 をあわせて対応し、`task-handle-termination!` で状態を `'terminated` にすると同時に reduction を `0` に設定し、現在実行中でないタスクは即座に Arena を O(1) リセット、実行中のタスクは次の safepoint（`check-safepoint!` / `safepoint-poll!`）で検知・脱出してタスク境界の出口で確実に Arena 等の資源を片付ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/723-link-kill-safepoint-and-cleanup-order`

1. `links.scm` の `task-handle-termination!` において、対象タスクの状態を `'terminated` に設定すると同時に `(task-reductions-set! task 0)` で reduction を `0` に強制設定する。
2. `preempt.scm` の `check-safepoint!` / `safepoint-poll!` を拡張し、`<budgeted-task>` および `<task-context>` の両方を受け付けられるようにするとともに、対象タスク（または `<budgeted-task>` の内部 target / `current-synapse-task`）の状態が `'terminated` の場合は reduction を再補充せず、reduction を `0` に保ったまま `task-escape-continuation`（または `on-exhaust-thunk` / `'terminated` 返却）で即座に計算ループから脱出させる。
3. `panic.scm` の `synapse-cleanup-task-resources!` および `%panic-with-synapse-task-boundary` において、先に `task-handle-termination!`（状態 `'terminated` 化＋reduction `0` 化＋リンク伝播・チャネル Poisoning）を実行し、タスクの実行停止を確認した後に最後に Arena の O(1) リセット（`arena-reset!` / `arena-secure-reset!`）を実行する順序（A4）に統一する。またタスク境界脱出時にも `state` が `'terminated` であれば確実に Arena をリセットする。
4. `test_links_monitors.scm` と `test_preemption.scm` に、Link 連鎖終了による reduction `0` 化・safepoint 即時脱出・実行停止後の Arena クリーンアップ順序のテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] Link による強制終了で対象タスクの reduction が `0` になり、次の safepoint で確実に実行が停止すること。
- [x] 実行停止が確認された後にのみ資源（Arena 等）が片付けられること。
- [x] `make -C ulisp test_links_monitors test_preemption test_let_it_crash lint_sexpr` がすべて PASS すること。

