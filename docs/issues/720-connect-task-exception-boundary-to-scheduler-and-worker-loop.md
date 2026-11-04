---
ID: 720
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] タスク境界への with-exception-handler 統合およびスケジューラ・Worker ループ例外防壁の接続 (ID: 720)

## 1. 概要 / Summary
現在、`with-synapse-task-boundary` は `call/cc` の脱出継続を設定するだけで R7RS の `error` や `raise` を捕まえておらず、さらに `scheduler-execute-task!` から `with-synapse-task-boundary` が呼ばれていない（項目 A2）。境界内で `with-exception-handler` を用いて `error` / `raise` もすべて捕捉し、`scheduler-execute-task!` から境界を呼び出すとともに、Worker ループにも最後の砦として `guard` を設置する。

### 再現手順 / Steps to Reproduce
1. スケジューラ上で実行されるタスク内で `(car '())` や `(error "boom")` を実行する。
2. `scheduler-execute-task!` が例外境界を通していないため、タスク単位の異常終了にならず Worker 全体が未捕捉例外で停止する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/scheduler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm)
- [ ] [exception.scm](../../ulisp/lib/exception.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `with-synapse-task-boundary` が `synapse-panic!` の明示的呼び出しのみを想定しており、`with-exception-handler` による一般例外（`error` / `raise`）の捕捉・パニック変換を行っていない。
- `scheduler-execute-task!` がタスクを実行する際に `with-synapse-task-boundary` を経由していない。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ユーザタスク側で手動で `guard` と `synapse-panic!` を記述する。
* **恒久対策 (Permanent Fix)**: `with-synapse-task-boundary` 内部に `with-exception-handler` を組み込み、`scheduler-execute-task!` から必ず境界を呼び出し、Worker ループにも最終防衛線の `guard` を配置する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/720-connect-task-exception-boundary`

1. `with-synapse-task-boundary` の中で `with-exception-handler` を使い、`error` と `raise` もすべて捕まえてタスクパニック処理へ流す。
2. `scheduler-execute-task!` から `with-synapse-task-boundary` を呼び出すように接続する。
3. Worker ループ（`%scheduler-worker-native-loop` 等）にも最後の砦として `guard` を置く。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] タスク内で発生した `(car '())`、`error`、`raise`、`synapse-panic!` がすべてタスク境界で捕捉され、他タスクや Worker スレッドを巻き込まないこと。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

