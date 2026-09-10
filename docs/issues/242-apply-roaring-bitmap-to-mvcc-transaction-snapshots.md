---
ID: 242
種別: Feature / Performance
優先度: High
ステータス: Open (New)
担当エージェント: Database / Data Infrastructure Specialist / Software Development (SWD)
---

# [FEAT/DB] src/database/transaction/mvcc.py における Roaring Bitmap を用いたトランザクション追跡とスナップショット分離の省メモリ・高速化 (ID: 242)

## 1. 概要 / Summary

自作DBMS基盤 `src/database/transaction/mvcc.py`（MVCCManager / TransactionSnapshot）において、トランザクションのコミット済み ID（`_committed_txs: Set[int]`）およびアクティブ ID（`_active_txs: Set[int]`）の管理を Python 標準 `set[int]` から [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) の `RoaringBitmap` へ換装する。

現在、`MVCCManager.begin_transaction()` が実行されるたびに `self.committed_tx_ids = set(committed_tx_ids)` による全件シャローコピーが発生しており、トランザクション数が増大するにつれてメモリ肥大化とハッシュ探索オーバーヘッドが深刻化する。連続する単調増加の TxID 特性を活かし、`RoaringBitmap`（`RunContainer` / `BitmapContainer`）を用いることで、スナップショット生成の `clone()` を $O(1) \sim O(\text{chunks})$ に高速化し、メモリ使用量を劇的に圧縮する。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/241-migrate-roaring-bitmap-to-core-structures.md`](file:///workspace/arxiv-security-papers/docs/issues/241-migrate-roaring-bitmap-to-core-structures.md)
- **設計書**: [`docs/designs/DSN-14-database_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-14-database_engine_architecture.md)
- **学術・業界参照**:
  - PostgreSQL `pg_xact` (Commit Log / CLOG) および Txid Snapshot アーキテクチャ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/transaction/mvcc.py`](file:///workspace/arxiv-security-papers/src/database/transaction/mvcc.py):
  - `TransactionSnapshot`: `active_tx_ids`, `committed_tx_ids` を `RoaringBitmap` に換装
  - `MVCCManager`: `_active_txs`, `_committed_txs`, `_aborted_txs` を `RoaringBitmap` に換装
  - `_check_xmin_visibility`, `_check_xmax_visibility`: 高速ビット判定（`val in bitmap`）へ更新
- [ ] [`tests/database/test_mvcc.py`](file:///workspace/arxiv-security-papers/tests/database/) (または既存 MVCC テスト):
  - スナップショット分離、ファントムリード防止、First-Committer-Wins の回帰テスト検証

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots`

1. **TransactionSnapshot の RoaringBitmap 化**:
   - `active_tx_ids: RoaringBitmap`, `committed_tx_ids: RoaringBitmap` を保持。
   - `snapshot = TransactionSnapshot(assigned_id, active_copy, self._committed_txs.clone())` による超高速クローン。
2. **可視性判定の最適化**:
   - `version.xmin in self.committed_tx_ids` を `RoaringBitmap.__contains__` で高速評価。
3. **コミット・アボート遷移の統合**:
   - `commit_transaction()`: `_active_txs.remove(tx_id)`, `_committed_txs.add(tx_id)`
   - `abort_transaction()`: `_active_txs.remove(tx_id)`, `_aborted_txs.add(tx_id)`
4. **テスト・品質検証**:
   - 並行トランザクションテスト、大量コミット時のメモリ削減ベンチマーク、Xenon Rank A、`mypy --strict` 検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `MVCCManager` および `TransactionSnapshot` が `core.structures.roaring_bitmap.RoaringBitmap` で動作すること。
- [ ] スナップショット生成時（`begin_transaction`）のメモリ複製オーバーヘッドが削減され、数万件のトランザクションでも安定動作すること。
- [ ] 既存のトランザクション分離性（Snapshot Isolation / Repeatable Read）および競合検出テストが全件 PASS すること。
- [ ] Xenon Rank A、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
