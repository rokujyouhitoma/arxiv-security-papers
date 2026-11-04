---
ID: 720
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] タスク境界への with-exception-handler 統合およびスケジューラ・Worker ループ例外防壁の接続 (ID: 720)

## 1. 概要 / Summary
現在、`with-synapse-task-boundary` は脱出継続を設定するだけで R7RS の `error` や `raise` を捕まえておらず、さらに `scheduler-execute-task!` から `with-synapse-task-boundary` が呼ばれていない（項目 A2）。境界内で `with-exception-handler` を用いて `error` / `raise` / 型エラー（`(car '())` 等）もすべて捕捉し、`scheduler-execute-task!` から境界を呼び出すとともに、Worker ループにも最後の砦として `guard` を設置する。

### 再現手順 / Steps to Reproduce
1. スケジューラ上で実行されるタスク内で `(car '())`、`(error "boom")`、または `(raise 'custom-exn)` を実行する。
2. `with-synapse-task-boundary` が `with-exception-handler` を持たず、`scheduler-execute-task!` も例外境界を通していないため、タスク単位の異常終了（パニックおよび資源クリーンアップ）にならず Worker 全体が未捕捉例外または `SIGSEGV` で停止する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/panic.scm`, `ulisp/runtime/concurrency/scheduler.scm`, `ulisp/runtime/concurrency/channel.scm`, `ulisp/backend/140_backend_x86_64.scm`, `ulisp/backend/142_backend_x86_freestanding.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [panic.scm](../../../ulisp/runtime/concurrency/panic.scm)
- [x] [scheduler.scm](../../../ulisp/runtime/concurrency/scheduler.scm)
- [x] [channel.scm](../../../ulisp/runtime/concurrency/channel.scm)
- [x] [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
- [x] [142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm)
- [x] [test_let_it_crash.scm](../../../tests/concurrency/test_let_it_crash.scm)
- [x] [test_scheduler.scm](../../../tests/concurrency/test_scheduler.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. `with-synapse-task-boundary` が `synapse-panic!` の明示的呼び出しのみを想定しており、`with-exception-handler` による一般例外（`error` / `raise`）の捕捉・`%execute-task-panic!` への変換を行っていない。
2. `scheduler-execute-task!` がタスク（`<task-context>`、`<budgeted-task>`、`<coroutine-context>`、サンク手続き）を実行する際に `with-synapse-task-boundary` を経由していない。また、`<task-context>` の `task-next-run` が手続きであっても実行されていなかった。
3. x86-64 ネイティブバックエンド（`140_backend_x86_64.scm`）において、`car` / `cdr` の `(%load %rax %rax -1)` / `(%load %rax %rax 7)` がペアタグ検査を行わずにメモリアクセスしていたため、`(car '())` 実行時に Scheme 例外ではなくハードウェア `SIGSEGV` が発生していた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: ユーザタスク側で手動で `guard` と `synapse-panic!` を記述する。
* **恒久対策 (Permanent Fix)**:
  1. `140_backend_x86_64.scm` および `142_backend_x86_freestanding.scm` にて `car` / `cdr` 実行時のペアタグ検査と `ulisp_pair_type_error`（Worker ごとの `ulisp_handler_chain` を巻き戻して `'type-error` を送出）を実装する。
  2. `with-synapse-task-boundary` 内部に `with-exception-handler` を組み込み、内部 `guard` で捕捉されなかった `error`、`raise`、`'type-error` をすべて `%execute-task-panic!` へルーティングする。
  3. `channel.scm` に `*synapse-task-boundary-hook-box*` と Worker ごとのフォールバック `<task-context>` を設け、`scheduler-execute-task!` から必ず境界を呼び出し、Worker ループ（`%scheduler-worker-native-loop`, `%scheduler-step-all!`, `scheduler-run-parallel!`）にも最終防衛線の `guard` を配置する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/720-connect-task-exception-boundary`

1. `140_backend_x86_64.scm` の `emit-x86-asm-inst` で `(mov rax (%disp -1 rax))` / `(mov rax (%disp 7 rax))` に対してペアタグ検査を追加し、`142_backend_x86_freestanding.scm` に `ulisp_pair_type_error` を実装して `compiler.scm` / `stage1` / `bin/ulisp-boot` を更新する。
2. `with-synapse-task-boundary`（`panic.scm` および `channel.scm` のデフォルトフック）の中で `with-exception-handler` を使い、`error` と `raise` もすべて捕まえて `%execute-task-panic!` へ流す。
3. `scheduler-execute-task!` から `*synapse-task-boundary-hook-box*` 経由で `with-synapse-task-boundary` を呼び出すように接続し、`<task-context>` の `task-next-run` 手続きも境界内で実行する。
4. Worker ループ（`%scheduler-worker-native-loop`, `%scheduler-step-all!`, `scheduler-run-parallel!`）にも最後の砦として `guard` を置く。
5. `test_let_it_crash.scm` と `test_scheduler.scm` に `(error "boom")`, `(raise 'custom)`, `(car '())` の境界捕捉・隔離テストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] タスク内で発生した `(car '())`、`error`、`raise`、`synapse-panic!` がすべてタスク境界で捕捉され、他タスクや Worker スレッドを巻き込まないこと。
- [x] `scheduler-execute-task!` が例外境界を経由し、Worker ループに最終防衛線の `guard` が設置されていること。
- [x] `make -C ulisp test_let_it_crash test_scheduler test_multithread_scheduler lint_sexpr` がすべて PASS すること。


