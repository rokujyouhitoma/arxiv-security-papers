---
ID: 744
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] Layer 1 (R7RS) ループおよび関数呼び出しへの強制終了 Safepoint 自動挿入 (ID: 744)

## 1. 概要 / Summary
タスクの中断や Link による強制終了 (`kill` / `brutal_kill`) を可能にするための状態確認 Safepoint が、現状 ASC カーネル（低レベルプリミティブ）にしか存在しない。
このため、標準的な Scheme (R7RS) で書かれた純粋な計算ループや再帰呼び出しを行うタスクは、外部から `kill` シグナルを受け取っても Safepoint を通過せず、停止されずに走り続けてしまう。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue: Follow-up of #723
- 関連資料: DSN-11 (並行性ランタイム仕様), Erlang/OTP プリエンプションモデル仕様

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [`ulisp/compiler/nanopass.scm`](../../ulisp/compiler/nanopass.scm)
- [ ] [`ulisp/compiler/passes/131_lir_safepoint.scm`](../../ulisp/compiler/passes/131_lir_safepoint.scm)
- [ ] [`ulisp/runtime/concurrency/preempt.scm`](../../ulisp/runtime/concurrency/preempt.scm)
- [ ] [`ulisp/tests/test_preemption.scm`](../../ulisp/tests/test_preemption.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/744-insert-safepoints-into-layer-1-loops-and-calls`

1. `ulisp/compiler/passes/131_lir_safepoint.scm`:
   - LIR 最適化・コード生成パスにおいて、以下の箇所に Safepoint ポーリング命令（または reductions カウンタ減算命令）を自動挿入する：
     - 各ループのバックエッジ (loop back-edge)
     - 関数・クロージャのプロローグ (function entry / tail call)
2. `ulisp/runtime/concurrency/preempt.scm`:
   - Safepoint 到達時にタスクの保留中シグナル（`kill`, `yield` 等）をチェックし、終了要求フラグが立っていれば速やかに `task-exit! 'killed` へ遷移させる。
3. `ulisp/tests/test_preemption.scm`:
   - 無限ループ `(let loop () (loop))` を実行中のタスクに対し、別タスクから `link-kill!` を発行した際に確実に停止することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] R7RS の末尾再帰およびループ構文に対してコンパイラが自動的に Safepoint を挿入すること
- [ ] ASC カーネル API を明示的に呼ばない純粋計算タスクであっても、外部からの kill シグナルで確実に停止すること
- [ ] Safepoint 挿入による通常実行時のオーバーヘッドが許容範囲内であること
- [ ] `ulisp/tests/test_preemption.scm` が PASS すること

