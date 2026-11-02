---
ID: 672
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] epoch-advance! におけるフェッチ後再読み取り競合の是正と同一 Epoch 重複返却の解消 (ID: 672)

## 1. 概要 / Summary
`ulisp/runtime/concurrency/epoch.scm` の `epoch-advance!` において、`atomic-fetch-add!` による原子的インクリメント完了後に、戻り値（加算前の値）を使用せず直後に `(epoch-current)` を再読み取りしているため、並行して `epoch-advance!` が実行された際に、異なる探索ブランチに同一の Epoch 番号が返却される重大な並行性バグ（CWE-362）を解消する。

### 再現手順 / Steps to Reproduce
1. スレッド A とスレッド B が同時に `(epoch-advance!)` を実行する。
2. スレッド A がインクリメント（カウンタ: 1 $\to$ 2）。
3. スレッド B がインクリメント（カウンタ: 2 $\to$ 3）。
4. スレッド A と B がそれぞれ `(epoch-current)` を呼び出し、双方が 3 を受け取る。
5. 独立した2つの投機実行ブランチに同一の Epoch 3 が紐付けられ、一方のロールバックでもう一方が誤終了する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / uLisp Concurrency Runtime
- File: [ulisp/runtime/concurrency/epoch.scm](ulisp/runtime/concurrency/epoch.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/epoch.scm](ulisp/runtime/concurrency/epoch.scm)
- [ ] [tests/concurrency/test_epoch.scm](tests/concurrency/test_epoch.scm)
- [ ] [tests/test_synapse_epoch.py](tests/test_synapse_epoch.py)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
`epoch.scm` の 36〜39行目の実装：
```scheme
(define (epoch-advance!)
  (begin
    (atomic-fetch-add! *epoch-global-counter* 1)
    (epoch-current)))
```
`atomic-fetch-add!` は更新前の古い整数値を原子的・決定論的に返しているにもかかわらず、その返り値を捨てて非アトミックに次の式 `(epoch-current)` でグローバル変数を再参照しているため、他スレッドのインクリメントが割り込むと最新値が重複して返される。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: Epoch 進行（探索チェックポイント発行）をシングルスレッド（Layer 1 制御プレーン）に限定する。
* **恒久対策 (Permanent Fix)**: `atomic-fetch-add!` の返り値に直接 1 を加えた値を返すよう変更し、再読み取り競合を根本排除する。
```scheme
(define (epoch-advance!)
  (+ (atomic-fetch-add! *epoch-global-counter* 1) 1))
```

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/672-epoch-advance-atomic-return-race`

1. `ulisp/runtime/concurrency/epoch.scm` の `epoch-advance!` を修正。
2. 並行ストレステストで `epoch-advance!` を複数スレッドから同時に数千回呼び出し、返却値の完全一意性を検証。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 並行して呼び出された全 `epoch-advance!` の戻り値が厳密にユニークであり、重複が 0 件であること。
- [ ] 既存の Epoch 破棄および世代ゲート検証テスト（`test_epoch.scm`）が 100% PASS すること。

