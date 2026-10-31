---
ID: 642
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 世代管理型投機タスク破棄および待機タスク世代ゲート検証の実装 (ID: 642)

## 1. 概要 / Summary
[DSN-37] Phase 4 Task 4.2 に基づき、コントロールプレーン側の `call/cc` バックトラック探索と連動して、無効化された世代（Epoch）に属する並列計算タスク群を即座に特定・強制アボートさせる世代管理型投機タスク破棄（Generation-Based Speculative Cancellation）機構を実装する。
あわせて、チャネル待機でスリープ中のタスクがゾンビ化するのを防止する世代ゲート検証（Generation Gate）機構を確立する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#146-phase-4-ホストカーネル境界--世代管理型投機タスク破棄) (第 8.2 節 世代管理型投機タスク破棄、第 8.3 節 待機中タスクのアボート保証、第 14.6 節 Task 4.2)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/epoch.scm` (新規: 世代管理およびロールバック制御)
- [ ] `tests/concurrency/test_speculative_cancellation.scm` (新規: call/cc 連動タスクアボートテスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/642-speculative-cancellation`

1. **グローバル世代カウンタ**:
   - コントロールプレーン側でチェックポイント作成時に Epoch ID を発行。
   - `spawn-task` 時にタスクの `task-epoch` フィールドにバインド。
2. **バックトラック検知とアボート発行**:
   - `call/cc` により過去のチェックポイントへ復帰した際、破棄された Epoch ID 以上のタスク群に対し「Aborted」シグナルを発行（`task-reductions` をアトミックに 0 化）。
3. **Generation Gate ガード**:
   - チャネル待機（`TASK_WAITING_CHANNEL`）から起床したタスクは、処理再開前に自身の Epoch と現在の有効 Epoch を比較検証。
   - 世代不一致を検知した場合は直ちに `TASK_TERMINATED` へ遷移し、アリーナを $O(1)$ 瞬時解放して消滅。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] コントロールプレーンが継続（`k`）を呼び出して過去に戻った際、進行中タスクが確実にアボートすること
- [ ] チャネル待機中のタスクが不整合なメッセージを受信することなく、起床直後にクリーンに破棄されること
- [ ] アボートされた全タスクのアリーナメモリが $O(1)$ で回収され、メモリリークが 0 であること
