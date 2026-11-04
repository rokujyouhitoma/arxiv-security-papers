---
ID: 730
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/SEC] プロセス名レジストリ synapse-send-named! のタスク宛て実配送・terminated 状態名統一・終了タスク自動登録解除 (ID: 730)

## 1. 概要 / Summary
現在、`registry.scm` の `synapse-send-named!`（`registry.scm:309-313`）では、登録先が `<task-context>` の場合に状態が `'dead` / `'panicked` / `'completed` でなければ**実際には何も送らずに `#t` を返している**（項目 C5）。さらに、タスク終了状態の名前が他モジュールの `'terminated` と不一致であり、死んだタスクの登録も自動で外れない。タスク宛ての `synapse-send-named!` で実際にメッセージを配送し、状態名を `'terminated` に揃え、死んだタスクの登録を自動で外すように修正する。

### 再現手順 / Steps to Reproduce
1. `<task-context>` を `(synapse-register! 'worker-a task)` で登録する。
2. `(synapse-send-named! 'worker-a 'hello)` を呼ぶと `#t` が返るが、`task` には何も届かない。
3. `task` が `task-handle-termination!` で `'terminated` 状態になっても、`synapse-send-named!` は `'dead` / `'panicked` / `'completed` しか見ていないため `'dead_process` にならず、レジストリからも消えない。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/registry.scm`, `ulisp/runtime/concurrency/links.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [registry.scm](../../ulisp/runtime/concurrency/registry.scm)
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [test_registry.scm](../../tests/concurrency/test_registry.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `synapse-send-named!` の `<task-context>` 分岐がスタブ実装（`#t` を返すだけ）のまま残っており、状態名も `'terminated` に統一されていなかったため。
- `task-handle-termination!` からレジストリの登録解除フックが呼ばれていないため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `<task-context>` ではなく `<channel>` をレジストリに登録する。
* **恒久対策 (Permanent Fix)**: タスク宛ての `synapse-send-named!` でタスクのメールボックス／handoff へ実際に配送して起床させ、状態判定を `'terminated` に揃え、タスク終了時にレジストリ登録を自動で解除する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/730-registry-send-named-and-auto-unregister`

1. `synapse-send-named!` の `<task-context>` 分岐で、状態を `'terminated`（および互換シンボル）でチェックし、生存時は実際にタスクへメッセージを配送して `task-wake!` を呼ぶ。
2. タスク終了時（`task-handle-termination!`）に、そのタスクを指しているレジストリエントリを自動で登録解除する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] タスク宛ての `synapse-send-named!` でメッセージが実際に配送されること。
- [ ] `'terminated` 状態のタスクが死んだタスクとして扱われ、終了時にレジストリ登録が自動で外れること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

