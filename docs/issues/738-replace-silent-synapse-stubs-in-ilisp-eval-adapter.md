---
ID: 738
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/SEC] ILisp / eval_adapter.scm における境界・Supervisor 無言スタブ (#f) の本実装統合および未対応機能の明示的エラー化 (ID: 738)

## 1. 概要 / Summary
現在、`eval_adapter.scm`（19〜75行目）において、`with-synapse-task-boundary` や `supervisor-handle-child-down!`、`synapse-panic!` などの処理が「何もせず `#f` を返す」スタブになっており、インタプリタ（ILisp）や `eval_adapter.scm` 単体利用時には障害処理が何も言わずに無効化される。ILisp で使う機能から本物の実装に置き換えるか、未対応機能は明示的な `error` を送出するように修正する。

### 再現手順 / Steps to Reproduce
1. `panic.scm` や `supervisor.scm` を後から上書きロードせずに `eval_adapter.scm` の環境で `(with-synapse-task-boundary task thunk)` を呼ぶ。
2. `thunk` すら実行されずに無言で `#f` が返り、障害処理やタスク実行が無効になる。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99 / ILisp)
- File: `ulisp/runtime/concurrency/eval_adapter.scm`, `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/supervisor.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [eval_adapter.scm](../../ulisp/runtime/concurrency/eval_adapter.scm)
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [links.scm](../../ulisp/runtime/concurrency/links.scm)
- [ ] [supervisor.scm](../../ulisp/runtime/concurrency/supervisor.scm)
- [ ] [test_eval_adapter.scm](../../tests/concurrency/test_eval_adapter.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `eval_adapter.scm` が単独でロードされた際の未定義シンボルエラーを避けるために配置されたフォールバックスタブが、何もせず `#f` を返すダミー関数のまま放置されていたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: `eval_adapter.scm` の後に必ず `links.scm`, `panic.scm`, `supervisor.scm` 等をすべてロードする。
* **恒久対策 (Permanent Fix)**: ILisp / `eval_adapter.scm` で使用する境界・パニック・Supervisor 等の機能を本物の実装に接続し、ネイティブ専用で動作できない機能については無言で `#f` を返すのではなく明示的な `error` を投げるようにする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/738-replace-eval-adapter-silent-stubs`

1. `eval_adapter.scm` の無言スタブ（`#f` 返却）を撤廃し、`panic.scm` / `links.scm` / `supervisor.scm` / `registry.scm` の本実装を利用可能にする。
2. インタプリタ環境でサポートしない低レベル機能がある場合は、無言で `#f` を返さず明示的なエラーを送出する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `eval_adapter.scm` / ILisp 実行時に `with-synapse-task-boundary` や `supervisor-handle-child-down!` が無言で `#f` を返すスタブになっておらず、本物の実装または明示的エラーとして動作すること。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

