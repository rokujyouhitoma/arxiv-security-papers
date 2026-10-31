---
ID: 635
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 分散 M:N ワークスティーリングスケジューラおよび Chase-Lev Deque の実装 (ID: 635)

## 1. 概要 / Summary
[DSN-37] Phase 2 Task 2.2 に基づき、システムの論理 CPU コア数分の OS ワーカースレッド間でタスクを自律分散する M:N スケジューラを実装する。
各ワーカが Chase-Lev ロックフリー両端キュー（Deque）を保持し、ローカル実行（LIFO）と他ワーカからの盗取（FIFO スティール）によりキャッシュ局所性と負荷分散を両立する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#144-phase-2-mn-スケジューラ--強プリエンプション) (第 7.1 節 M:N スケジューラ、第 14.4 節 Task 2.2)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/scheduler.scm` (新規: M:N ワークスティーリングスケジューラ)
- [ ] `ulisp/runtime/concurrency/deque.scm` (新規: Chase-Lev ワークスティーリング Deque)
- [ ] `tests/concurrency/test_scheduler.scm` (新規: ワークスティーリング負荷分散テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/635-work-stealing-scheduler`

1. **Chase-Lev Deque**:
   - ワーカ自身は末尾（Bottom）に対して `push` / `pop`（スレッドセーフ・単一スレッドアクセス）。
   - 他ワーカは先頭（Top）から CAS で `steal`（複数スレッドアクセス対応）。
2. **ワーカーループ**:
   - 自 Deque からタスクを取り出して実行。
   - 自キューが空になった場合、擬似乱数で他ワーカを選択し、その Top からタスクをスティール。
   - 全ワーカが空の場合は指数バックオフまたは条件変数待機。
3. **可観測性フィールドの更新**:
   - スティール発生時に `task-steals-count` をアトミックに加算。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ワーカースレッド間でのタスクスティールが正常に行われること
- [ ] 不均等な負荷のタスク群を投入した際、全ワーカの CPU 稼働率がフラットに平準化されること
- [ ] ワーカの停止およびシャットダウン処理がクリーンに完了すること
