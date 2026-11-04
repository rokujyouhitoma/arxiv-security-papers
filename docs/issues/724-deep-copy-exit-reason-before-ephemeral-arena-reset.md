---
ID: 724
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] タスク終了理由のディープコピー退避と Arena リセット順序の是正 (ID: 724)

## 1. 概要 / Summary
現在、`synapse-cleanup-task-resources!`（`panic.scm:72-80`）では、先にタスクの Ephemeral Arena をリセット（またはゼロスクラブ）してから、`task-handle-termination!` を呼んで終了理由（`panic-reason`）を Monitor / Link 先へ通知している（項目 B5）。終了理由をディープコピーしてから通知を送り、Arena のリセットは最後に行うよう順序を是正する。

### 再現手順 / Steps to Reproduce
1. タスクの Arena 上に構築されたデータ構造を含む終了理由で `synapse-secure-panic!` または `synapse-panic!` を呼び出す。
2. `synapse-cleanup-task-resources!` の Step 1 で Arena がリセット・ゼロクリアされた後、Step 2 で `task-handle-termination!` により Monitor / Link へ通知が送られるため、破壊されたメモリが参照される。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/boundary.scm`, `ulisp/runtime/concurrency/links.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [boundary.scm](../../ulisp/runtime/concurrency/boundary.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `synapse-cleanup-task-resources!` 内で Arena リセット（Step 1）と `task-handle-termination!` による終了通知（Step 2）の実行順序が逆転しており、さらに終了理由のディープコピーが行われていないため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 終了理由には即値（シンボルや整数）のみを渡す。
* **恒久対策 (Permanent Fix)**: 終了理由（および詳細）をディープコピーしてから終了通知（Monitor `DOWN` / Link `EXIT` / Crash Logger）を行い、Arena のリセットは処理の最後に実行する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/724-deep-copy-exit-reason-before-arena-reset`

1. タスク終了・パニック処理時に、終了理由オブジェクトを `sanitize-from-arena` / `channel-deep-copy` でディープコピーする。
2. コピーした終了理由を用いて Monitor / Link / Channel Poison の通知を完了させる。
3. すべての通知が完了した最後に `arena-reset!` / `arena-secure-reset!` を実行する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 複合データ（リスト・ベクタ・文字列等）の終了理由がディープコピーされて Monitor / Link 先へ正確に届き、その後に Arena がリセットされること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

