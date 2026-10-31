---
ID: 633
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装 (ID: 633)

## 1. 概要 / Summary
[DSN-37] Phase 1 Task 1.2 に基づき、1対1 の所有権移譲を保証する線形所有権移譲通信チャネル（`make-channel`, `channel-send!`, `channel-recv!`）を実装する。
容量 0 のランデブー同期および容量 $>0$ の有界バッファをサポートし、下流の遅延時に上流プロデューサを自動サスペンドさせる決定論的バックプレッシャー機構を確立する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#143-phase-1-通信--ロックフリー同期) (第 4 章 並行通信モデル、第 4.3.1 節 バックプレッシャー、第 14.3 節 Task 1.2)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/channel.scm` (新規: 線形所有権移譲チャネル構造体および操作 API)
- [ ] `tests/concurrency/test_channel.scm` (新規: チャネル同期・有界テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/633-linear-channel`

1. **チャネル構造体**:
   - `message-queue`, `recv-wait-queue`, `send-wait-queue`, `capacity`, `current-count` を保持。
2. **channel-send! の動作**:
   - 受信待ちタスクがいれば即座にメッセージを Move 渡ししてタスクを起床（ランキュー投入）。
   - 受信待ちがおらず、バッファ空きがあればメッセージキューへエンキュー。
   - バッファ満杯（`current-count >= capacity`）の場合は送信タスクを `TASK_WAITING_CHANNEL` に遷移させ `send-wait-queue` に登録してサスペンド。
3. **channel-recv! の動作**:
   - キューにメッセージがあればデキューし、送信待ちタスクがいれば 1 つ起床させてランキューへ。
   - キューが空ならタスクを `recv-wait-queue` に登録してサスペンド。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] ランデブー同期（capacity = 0）で送信側と受信側が互いに待ち合わせて同期すること
- [ ] 有界バッファ（capacity > 0）で満杯時に送信タスクが確実にサスペンドすること
- [ ] メッセージ受信に伴い送信待機タスクが起床すること（バックプレッシャー解消）
- [ ] 送受信で渡されるポインタの同一性（ゼロコピー Move）が検証されること
