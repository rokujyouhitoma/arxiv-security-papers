---
ID: 672
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] epoch-advance! におけるフェッチ後再読み取り競合の是正と同一 Epoch 重複返却の解消 (ID: 672)

## 1. 概要 / Summary
`ulisp/runtime/concurrency/epoch.scm` の `epoch-advance!` において、`atomic-fetch-add!` による原子的インクリメント完了後に、戻り値（加算前の古い値）を破棄し、直後に `(epoch-current)` を非アトミックに再読み取りしている。
このため、マルチワーカー環境で並行して `(epoch-advance!)` が呼び出された際に、異なる探索世代に対して同一の Epoch 番号が返却される重大な並行性バグ（Race Condition / TOCTOU 類似, CWE-362）を解消する。

### 再現手順 / Steps to Reproduce
1. スレッド A とスレッド B が同時に `(epoch-advance!)` を実行する。
2. スレッド A がインクリメント（カウンタ: $1 \to 2$）。
3. 直後にスレッド B がインクリメント（カウンタ: $2 \to 3$）。
4. スレッド A が `(epoch-current)` を参照 $\to$ **3** を取得。
5. スレッド B が `(epoch-current)` を参照 $\to$ **3** を取得。
6. 互いに独立した2つの探索・投機ブランチに同一の Epoch 3 が割り当てられ、一方の枝刈りロールバック（`epoch-rollback-to!`）により他方の正常な並列タスク群が誤って巻き添えアボート（CWE-400 / 状態破壊）される。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / uLisp Concurrency Runtime (Native AOT & Dual-Mode Interpreter)
- File: [ulisp/runtime/concurrency/epoch.scm](../../ulisp/runtime/concurrency/epoch.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/concurrency/epoch.scm](../../ulisp/runtime/concurrency/epoch.scm)
- [x] [tests/concurrency/test_epoch.scm](../../tests/concurrency/test_epoch.scm)
- [x] [tests/concurrency/concurrency_harness.scm](../../tests/concurrency/concurrency_harness.scm)
- [x] [docs/designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
`epoch.scm` の 36〜39行目の実装：
```scheme
(define (epoch-advance!)
  (begin
    (atomic-fetch-add! *epoch-global-counter* 1)
    (epoch-current)))
```
1. **なぜ非アトミック再読み取りが生じたのか**: `atomic-fetch-add!` が「加算前の古い値（old value）」を返す仕様であるため、インクリメント後の最新値を得る目的で安易に後続の `(epoch-current)` を呼び出していた。
2. **なぜ同一値が重複返却されるのか**: `atomic-fetch-add!` による書き込みと `epoch-current` による読み取りが分離しており、不可分操作（Atomic Transaction）になっていない。複数スレッドが挟み込まれた場合、遅れてインクリメントした側の最新値を先行スレッドも読み取ってしまう。
3. **セキュリティ脅威（STRIDE / CWE）**:
   - **CWE-362 (Race Condition)**: 世代カウンタのフェッチ後再読み取り競合。
   - **CWE-662 (Improper Synchronization)**: 投機的タスク破棄の世代バウンダリ破壊。
   - **CWE-400 (Resource Exhaustion / サービス停止)**: 健全な並行タスクが誤アボートされ、計算パイプラインがデッドロックまたは異常終了する。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Epoch 進行（探索チェックポイント発行）をシングルスレッド（Layer 1 コントロールプレーンの直列実行）に限定し、ワーカー並列下での `epoch-advance!` 呼び出しを禁止する。
* **恒久対策 (Permanent Fix)**:
  `atomic-fetch-add!` が返す加算前の値に 1 を加算した値を直接返却するよう数理的に単純化する：
  ```scheme
  (define (epoch-advance!)
    (+ (atomic-fetch-add! *epoch-global-counter* 1) 1))
  ```
  これにより、追加のメモリアクセスや再読み取りを行うことなく、不可分に更新された一意な Epoch 番号が呼び出し元へ決定論的に返される。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/672-epoch-advance-atomic-return-race`

### Step 1: `ulisp/runtime/concurrency/epoch.scm` の修正
1. `(define (epoch-advance!) ...)` の本体を `(+ (atomic-fetch-add! *epoch-global-counter* 1) 1)` へ変更。
2. `epoch-reset-global!` 呼び出し時にも `*epoch-global-counter*` のアトミック整合性を維持。

### Step 2: `tests/concurrency/test_epoch.scm` のアサーション拡充
1. Group 1「Epoch Counter & Transitions」において、複数回の連続 `(epoch-advance!)` 呼び出しが厳密に連続した一意の整数値を返すことをアサート。
2. `(epoch-current)` との完全同期を検証。

### Step 3: `tests/concurrency/concurrency_harness.scm` への並行 Epoch 進行アサーション追加
1. シナリオ 3（投機タスクキャンセル）または専用サブシナリオにおいて、Jitter 注入下で複数タスクが同時に `epoch-advance!` を呼び出した際に、取得した Epoch 番号群に一切の重複が存在しないことをアサート。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `epoch.scm` 内で `epoch-advance!` がフェッチ後再読み取り（`(epoch-current)`）を行わず、原子的加算結果を直接返していること。
- [x] `make -C ulisp test_epoch` が全ケース PASS（43 passed 以上、実測 49 passed）すること。
- [x] `make -C ulisp test_concurrency_harness` が 100 反復すべて 100% PASS（9,800 アサーション全件 PASS）すること。
- [x] 相対パス規則（Gate 3）の完全適合（絶対パス 0 件）。
