---
ID: 721
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG/SEC] エフェメラルアリーナ溢れ時の error をタスク局所 synapse-panic! へ分離 (ID: 721)

## 1. 概要 / Summary
`arena.scm` のオーバーフローチャンク上限超過（`arena.scm:105`）等で通常の `error` が呼ばれているため、アリーナが溢れた際にそのタスクだけの Fail-Fast 終了にならずランタイムエラーとして扱われる（項目 A3）。`error` をプログラム契約違反とタスク局所パニックの2種類に分け、アリーナ溢れを `synapse-panic!`（`'arena-overflow`）に変更して当該タスクのみが落ちるようにする。

### 再現手順 / Steps to Reproduce
1. タスク内でエフェメラルアリーナの最大チャンク数（`*arena-max-chunks*` = 64）を超えてメモリ割り当てを行う。
2. `arena.scm:105` で `(error "arena-overflow-fallback!: maximum overflow chunks exceeded (CWE-400 guard)" max-c)` が送出され、パニック理由が `'error` となり `'arena-overflow` として区別できない。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/arena.scm`, `ulisp/runtime/concurrency/panic.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [arena.scm](../../../ulisp/runtime/concurrency/arena.scm)
- [x] [panic.scm](../../../ulisp/runtime/concurrency/panic.scm)
- [x] [test_arena.scm](../../../tests/concurrency/test_arena.scm)
- [x] [test_let_it_crash.scm](../../../tests/concurrency/test_let_it_crash.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- Issue #630 で `arena.scm` を実装した時点では `panic.scm`（Issue #668）が存在しておらず、API 引数の型違反（CWE-843/CWE-190）とタスク資源上限超過（CWE-400 チャンク溢れ）の双方に標準の `error` を使用していたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: アリーナ割り当て前に残りチャンク数を手動で確認する。
* **恒久対策 (Permanent Fix)**: `arena.scm` に `*arena-overflow-panic-hook-box*` と `arena-overflow-panic!` を導入し、`panic.scm` でタスク境界内の場合は `(synapse-panic! reason msg max-c)` を呼び出すフックを接続する。これにより `arena.scm:105` のチャンク上限超過がタスク局所の `synapse-panic!`（理由 `'arena-overflow`）となり、該当タスクのみが Fail-Fast 終了してアリーナが O(1) 即時リセットされる。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/721-arena-overflow-synapse-panic`

1. `arena.scm` におけるエラー送出を「API 引数型・境界違反の `error`」と「タスク資源上限超過の `arena-overflow-panic!`（`synapse-panic!` 連携）」の2種類に整理する。
2. `%arena-allocate-new-chunk!`（`arena.scm:105`）のチャンク上限超過時に `(arena-overflow-panic! 'arena-overflow "arena-overflow-fallback!: maximum overflow chunks exceeded (CWE-400 guard)" max-c)` を呼び出し、`panic.scm` 側でアクティブなタスク境界が存在する場合に `(synapse-panic! reason msg max-c)` を発動させる。
3. `test_let_it_crash.scm` および `test_arena.scm` にアリーナ溢れが `'arena-overflow` パニックとして当該タスクのみを終了させ、アリーナを自動 O(1) リセットし、他タスクに影響しないことを検証するテストを追加する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] アリーナ溢れ発生時に `synapse-panic!`（理由 `'arena-overflow`）が呼ばれ、当該タスクのみが異常終了し、他タスクの実行に影響しないこと。
- [x] `make -C ulisp test_arena test_let_it_crash lint_sexpr` がすべて PASS すること。


