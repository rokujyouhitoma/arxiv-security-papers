---
ID: 723
種別: Bug
優先度: High
ステータス: Open (New)
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
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [preempt.scm](../../ulisp/runtime/concurrency/preempt.scm)
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `task-handle-termination!` が `task-state-set!` のみを呼び、対象タスクの reduction カウンタを 0 にする処理や、`check-safepoint!` 側で `'terminated` 状態を検知してタスク境界へ脱出させる処理が欠落している。
- `synapse-cleanup-task-resources!` が対象タスクの実行停止（`'running` 状態でないこと）を確認する前に Arena をリセットしている。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: タスク側で手動で `(eq? (task-state self) 'terminated)` をポーリングする。
* **恒久対策 (Permanent Fix)**: B6 と A4 をあわせて対応し、強制終了時に状態を `'terminated` にした上で reduction を `0` にして safepoint で脱出させ、実行停止を確認した後に資源（Arena・Channel）を片付ける。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/723-link-kill-safepoint-and-cleanup-order`

1. Link 等による強制終了時に、対象タスクの状態を `'terminated` にしたうえで `task-reductions-set!` で reduction を `0` に設定する。
2. `check-safepoint!` / `safepoint-poll!` で `'terminated` 状態を検知した際、reduction を再補充せず即座にタスクの脱出継続へ抜けさせる。
3. 実行が止まったことを確かめてから Arena リセット等の資源後始末を行う手順（A4）を実装する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] Link による強制終了で対象タスクの reduction が `0` になり、次の safepoint で確実に実行が停止すること。
- [ ] 実行停止が確認された後にのみ資源（Arena 等）が片付けられること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

