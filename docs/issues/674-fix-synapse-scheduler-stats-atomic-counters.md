---
ID: 674
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] スケジューラ統計カウンタのアトミック化による並行終了判定の不整合・ハング防止 (ID: 674)

## 1. 概要 / Summary
`ulisp/runtime/concurrency/scheduler.scm` において、タスクの生成累計数（`tasks-spawned`）および完了累計数（`tasks-completed`）のインクリメント処理が通常の Scheme ベクタに対する非アトミックな更新で行われているため、マルチコア環境下でカウントのロスト（Lost Update, CWE-362）が発生し、スケジューラの完了待機ループ（`scheduler-run-until-done`）が早期終了または永久ハングする致命的な競合を解消する。

### 再現手順 / Steps to Reproduce
1. 複数ワーカースレッド（4ワーカー以上）を起動した状態で、短命なマイクロタスクを大量（数万〜数十万個）に投入する。
2. `(scheduler-run-until-done sched)` で全タスク完了を待機する。
3. `tasks-spawned` や `tasks-completed` の更新競合により、全タスクの処理が完了しているにもかかわらず `(>= tasks-completed tasks-spawned)` が成立せず永久ループする、あるいはタスク実行中に誤って早期脱出する事象が発生する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / uLisp Concurrency Runtime
- File: [ulisp/runtime/concurrency/scheduler.scm](ulisp/runtime/concurrency/scheduler.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/scheduler.scm](ulisp/runtime/concurrency/scheduler.scm)
- [ ] [tests/concurrency/test_scheduler.scm](tests/concurrency/test_scheduler.scm)
- [ ] [tests/concurrency/concurrency_harness.scm](tests/concurrency/concurrency_harness.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
`scheduler.scm` の 193〜199行目の実装：
```scheme
(define (%scheduler-tasks-spawned-inc! sched)
  (let ((s (%scheduler-stats sched)))
    (vector-set! s 0 (+ (vector-ref s 0) 1))))

(define (%scheduler-tasks-completed-inc! sched)
  (let ((s (%scheduler-stats sched)))
    (vector-set! s 1 (+ (vector-ref s 1) 1))))
```
`%scheduler-stats` は通常の Scheme ベクタ（`make-vector 4`）であり、複数の OS スレッド（ワーカースレッド）が同時に要素を読み取り・書き換える。アトミックなハードウェア命令（LOCK XADD や CAS ループ）を使用していないため、並行書き換え時に値が巻き戻り、累計カウンタが真のタスク数よりも小さくなる。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: 単一ワーカースレッドでのみタスク生成・完了を行う。
* **恒久対策 (Permanent Fix)**: `%scheduler-stats` の各要素（または構造体内部）を `<atomic-box>` に変更し、更新を `(atomic-fetch-add! box 1)` による原子的インクリメントへ置き換える。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/674-scheduler-stats-atomic-counters`

1. `make-work-stealing-scheduler` において、`spawned-box` および `completed-box` をそれぞれ `make-atomic-box` で初期化。
2. `%scheduler-tasks-spawned-inc!` および `%scheduler-tasks-completed-inc!` を `(atomic-fetch-add! ... 1)` で実装。
3. `scheduler-tasks-spawned` および `scheduler-tasks-completed` のアクセサを `atomic-ref` に変更。
4. 並行ハーネスで 100,000 マイクロタスクの投入・完了を検証し、カウントの完全一致（差分 0）を確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] マルチコア並行下で 100,000 タスク実行時、`scheduler-tasks-spawned` と `scheduler-tasks-completed` が完全に一致すること。
- [ ] `scheduler-run-until-done` がハングや早期終了を起こさず、決定論的に正常復帰すること。

