---
ID: 804
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] L1 Bounded Ring Buffer (256エントリ CAS-Free キュー) 導入によるタスク Push/Pop 高速化 (ID: 804)

## 1. 概要 / Summary
Go の Goroutine スケジューラにおける P ローカル実行キューは、256 エントリの固定長循環配列（Circular Ring Buffer）を採用しており、自ワーカーからの Push/Pop は CAS 不要、アトミックなインデックス加算（1〜2 CPU 命令）のみで完結する。
一方、現在の Synapse のワークスティーリングスケジューラは、全タスクを Chase-Lev デック（可変長配列）に投入しており、動的配列拡張チェックやポインタ多重間接参照、メモリバリアのオーバーヘッドが存在する。
本 Issue では、各ワーカーのフロントエンドに **L1 256エントリ固定長リングバッファ（CAS-Free Run-Queue）** を導入し、L1 キューが満杯になった場合のみ L2 Chase-Lev デックへバッチ退避する二層キュー構造を確立する。これにより、ワーカーローカルなタスク投入・取得オーバーヘッドを 120ns から 15ns 前後へ大幅圧縮する。

---

## 2. トレーサビリティ / Traceability
- [DSN-37: Synapse Dual-Plane Architecture](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Section 7.2 (Chase-Lev Stealing)
- [concurrency_evaluation.md](../benchmarks/concurrency_evaluation.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime/concurrency/deque.scm](../../ulisp/runtime/concurrency/deque.scm) - L1 Bounded Ring Buffer のデータ構造および Push/Pop 操作の実装
- [ ] [ulisp/runtime/concurrency/scheduler.scm](../../ulisp/runtime/concurrency/scheduler.scm) - ワーカーのローカルタスク投入・取得ホットパスの L1 二層化
- [ ] [tests/concurrency/test_queue.scm](../../tests/concurrency/test_queue.scm) - L1 リングバッファ単体テストおよびオーバーフロー退避検証
- [ ] [tests/concurrency/test_scheduler.scm](../../tests/concurrency/test_scheduler.scm) - スケジューラ結合テスト
- [ ] [benchmarks/concurrency/bench_microtasks.scm](../../benchmarks/concurrency/bench_microtasks.scm) - キュー操作スループット測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/804-implement-l1-bounded-ring-buffer-for-worker-local-queue`

1. ワーカーごとに固定長 256 要素のベクタ `l1-ring-buffer`、`head`、`tail` を配置。
2. 自ワーカーからの `push` は `tail = (tail + 1) & 255` で即座に格納（CAS なし）。
3. 自ワーカーからの `pop` は `tail = (tail - 1) & 255` で即座に取得。
4. L1 キュー満杯時（`tail - head >= 256`）は、半分（128個）を一括で L2 Chase-Lev デックまたはグローバルキューへバッチ退避。
5. 他ワーカーからの Work Stealing は L2 デックまたは L1 キューの `head` から安全に行う。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] L1 256エントリのリングバッファが導入され、ローカル Push/Pop が CAS なし・極小命令で実行されること。
- [ ] L1 満杯時の L2 デックへのバッチ退避および空時のバッチ補充が正常に動作すること。
- [ ] Work Stealing の整合性が保たれ、タスク消失や重複実行がゼロであること。
- [ ] 全並行性テストスイートが 100% PASS すること。

