---
ID: 724
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] タスク終了理由のディープコピー退避と Arena リセット順序の是正 (ID: 724)

## 1. 概要 / Summary
現在、`synapse-cleanup-task-resources!`（`panic.scm`）および `task-handle-termination!`（`links.scm`）では、終了理由（`panic-reason` / `details`）をディープコピーせずにそのまま Monitor / Link / Channel Poison 先へ渡している（項目 B5）。終了理由（およびパニック詳細）をディープコピーしてから通知を送り、Arena のリセットは最後に行うよう改修する。

### 再現手順 / Steps to Reproduce
1. タスクの Arena またはタスク局所バッファ上に構築された複合データ構造（ペア・ベクタ・文字列・バイトベクタ）を含む終了理由で `synapse-secure-panic!` または `synapse-panic!` を呼び出す。
2. 終了理由がディープコピーされないまま Monitor / Link へ通知が送られたり、Arena が先にリセットされたりすると、共有ポインタ残留や破壊されたメモリの参照が発生する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/links.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [panic.scm](../../../ulisp/runtime/concurrency/panic.scm)
- [x] [links.scm](../../../ulisp/runtime/concurrency/links.scm)
- [x] [test_let_it_crash.scm](../../../tests/concurrency/test_let_it_crash.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `synapse-cleanup-task-resources!`、`%execute-task-panic!`、および `task-handle-termination!` において、終了理由オブジェクトやパニック詳細リストに対して構造的ディープコピー（`channel-deep-copy`）を実行していなかったため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 終了理由には即値（シンボルや整数）のみを渡す。
* **恒久対策 (Permanent Fix)**: `links.scm` の `task-handle-termination!` および `panic.scm` の `%execute-task-panic!` / `synapse-cleanup-task-resources!` / `%panic-with-synapse-task-boundary` において、終了理由と詳細を `channel-deep-copy` でディープコピーしてから終了通知（Monitor `DOWN` / Link `EXIT` / Channel Poison / Crash Logger）を行い、Arena のリセットはすべての通知が完了した最後に実行する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/724-deep-copy-exit-reason-before-arena-reset`

1. `panic.scm` に `synapse-deep-copy-reason`（`channel-deep-copy` を用いた再帰的ディープコピー）を導入し、`%execute-task-panic!`、`%panic-with-synapse-task-boundary`、`synapse-cleanup-task-resources!` で `reason` および `details` を Arena リセット前にディープコピーする。
2. `links.scm` の `task-handle-termination!` においても、`reason` を `channel-deep-copy` でディープコピーしてから Channel Poisoning、各 Monitor への `DOWN` 通知、各 Link への `EXIT` 通知へ配送する。
3. すべての通知が完了した最後に `arena-reset!` / `arena-secure-reset!` を実行することを保証する。
4. `test_let_it_crash.scm`（Group 10）に、複合データ（リスト・ベクタ・文字列）を含む終了理由でパニックさせた際、ディープコピーされた独立ポインタの終了理由が Monitor / Link 先へ届き、元のオブジェクトを破壊しても通知先データが不変であり、かつ最後に Arena がリセットされることを検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 複合データ（リスト・ベクタ・文字列等）の終了理由がディープコピーされて Monitor / Link 先へ正確に届き、その後に Arena がリセットされること。
- [x] `make -C ulisp test_let_it_crash test_links_monitors test_boundary lint_sexpr` がすべて PASS すること。

