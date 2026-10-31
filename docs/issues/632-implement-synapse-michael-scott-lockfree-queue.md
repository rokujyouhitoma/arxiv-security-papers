---
ID: 632
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Michael-Scott ノンブロッキング・ロックフリーキューの実装 (ID: 632)

## 1. 概要 / Summary
[DSN-37] Phase 1 Task 1.1 に基づき、スピンロックを排除した CAS ベースの Michael-Scott ノンブロッキング FIFO キューを Pure Scheme で実装する。
チャネル内部のメッセージバッファおよび待機タスクキューとして機能し、キャッシュラインバウンスと CPU 浪費を根本排除する。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md#143-phase-1-通信--ロックフリー同期) (第 6 章 排他制御、第 14.3 節 Task 1.1)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/runtime/concurrency/queue.scm` (新規: Michael-Scott キュー実装)
- [ ] `tests/concurrency/test_queue.scm` (新規: ロックフリーキュー並行単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/632-michael-scott-queue`

1. **データ構造定義**:
   - `(define-record-type <queue-node> (make-queue-node value next) ...)`
   - `(define-record-type <lock-free-queue> (make-lock-free-queue head tail) ...)`
   - 初期化時にダミーノードを 1 つ確保し `head` と `tail` の両方を指す。
2. **Enqueue アルゴリズム**:
   - テールノードの `next` を CAS で新ノードへ付け替え、成功後に `tail` を新ノードへ CAS 推進。
3. **Dequeue アルゴリズム**:
   - `head` の次ノード（`next`）の値を読み出し、`head` を `next` へ CAS 推進。空なら `#f` を返却。
4. **ABA 抑止策**:
   - チャネル専用の事前確保済み固定長フリーリストを採用。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 単一スレッドでの FIFO 順序整合性テスト PASS
- [ ] 複数スレッドからの高頻度 Concurrent Enqueue/Dequeue でデータ欠損・順序逆転が 0 件
- [ ] 空キューからの Dequeue が即座に `#f` を返すこと
- [ ] すべての内部リンクが相対パスリンク規約に準拠していること
