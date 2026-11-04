---
ID: 721
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] エフェメラルアリーナ溢れ時の error をタスク局所 synapse-panic! へ分離 (ID: 721)

## 1. 概要 / Summary
`arena.scm` のオーバーフローチャンク上限超過（`arena.scm:105`）等で通常の `error` が呼ばれているため、アリーナが溢れた際にそのタスクだけの Fail-Fast 終了にならずランタイムエラーとして扱われる（項目 A3）。`error` をプログラム契約違反とタスク局所パニックの2種類に分け、アリーナ溢れを `synapse-panic!` に変更して当該タスクのみが落ちるようにする。

### 再現手順 / Steps to Reproduce
1. タスク内でエフェメラルアリーナの最大チャンク数（`*arena-max-chunks*` = 64）を超えてメモリ割り当てを行う。
2. `arena.scm:105` で `(error "arena-overflow-fallback!: maximum overflow chunks exceeded (CWE-400 guard)" max-c)` が送出される。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/runtime/concurrency/arena.scm`, `ulisp/runtime/concurrency/panic.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [arena.scm](../../ulisp/runtime/concurrency/arena.scm)
- [ ] [panic.scm](../../ulisp/runtime/concurrency/panic.scm)
- [ ] [test_arena.scm](../../tests/concurrency/test_arena.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- Issue #630 で `arena.scm` を実装した時点では `panic.scm`（Issue #668）が存在しておらず、CWE-400 ガードとして標準の `error` を使用していたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: アリーナ割り当て前に残りチャンク数を手動で確認する。
* **恒久対策 (Permanent Fix)**: `arena.scm:105` のアリーナ溢れエラーを `synapse-panic!` に変更し、そのタスクだけが Fail-Fast で終了してアリーナが即時リセットされるようにする。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/721-arena-overflow-synapse-panic`

1. `arena.scm` におけるエラー送出を「API 引数型違反などの `error`」と「タスク資源上限超過の `synapse-panic!`」の2種類に整理する。
2. `%arena-allocate-new-chunk!`（`arena.scm:105`）のチャンク上限超過時に `synapse-panic!` を呼び出し、該当タスクのみが落ちるようにする。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] アリーナ溢れ発生時に `synapse-panic!` が呼ばれ、当該タスクのみが異常終了し、他タスクの実行に影響しないこと。
- [ ] `make format`, `make static_analysis`, `make test` がすべて PASS すること。

