---
ID: 383
種別: Architecture
優先度: Medium
ステータス: Open (New)
---

# [ARCH/REFACTOR] トランザクション開始時の全テーブルディープコピー廃止および Pager / SlottedPage ストレージ層の統合 (ID: 383)

## 1. 概要 / Summary

PyNYTProf のプロファイリングおよびコード静的解析により、トランザクション管理と基盤ストレージ層に以下のアーキテクチャ上の課題が判明した：
1. **トランザクション開始時の全メモリ複製**: `SQLExecutor._exec_begin_tx` において、`BEGIN TRANSACTION` が呼ばれるとデータベース内のすべてのテーブルの全メタデータと全ベクトルをメモリ上に辞書複製（Deep Copy）している。テーブルサイズが大きくなると、トランザクション開始だけでメモリ枯渇および著しいレイテンシスパイクを引き起こす。
2. **ストレージエンジンのアーキテクチャ分断**: プロジェクト内には 4KB ページ管理を行う `Pager`, `2Q PageCache`, `WALWriter`, `SlottedPage`、および列指向の `PAXTable` や `MVCCManager` などの高度なストレージプリミティブが完備されている。しかし、`SQLExecutor` はこれらを利用せず、単一 JSON ファイル＋フラット配列の `VectorStorage` のみをデフォルトストレージとして使用している。

本 Issue では、トランザクション開始時の全件ディープコピーを廃止して変更行のみを追跡するトランザクションログ / ステージング方式へ是正するとともに、`Pager` / `SlottedPage` ストレージ層を SQL 実行エンジンのバックエンドとして接続可能にする設計統合を行う。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (4-Tier Storage: VFS, Pager, VDBE, Compiler)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/sql/executor.py` (`_exec_begin_tx`, `_restore_rollback_snapshot`)
  - `src/database/storage/pager.py` (`Pager`, `PageCache`)
  - `src/database/storage/slotted_page.py` (`SlottedPage`)
  - `src/database/transaction/mvcc.py` (`MVCCManager`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`_exec_begin_tx`, `_restore_rollback_snapshot`, `TransactionManager`)
- [ ] [`src/database/sql/transaction.py`](file:///workspace/arxiv-security-papers/src/database/sql/transaction.py) (`TransactionManager`)
- [ ] [`src/database/storage/pager.py`](file:///workspace/arxiv-security-papers/src/database/storage/pager.py)
- [ ] [`src/database/storage/slotted_page.py`](file:///workspace/arxiv-security-papers/src/database/storage/slotted_page.py)
- [ ] [`tests/database/transaction/test_mvcc_and_ss2pl.py`](file:///workspace/arxiv-security-papers/tests/database/transaction/test_mvcc_and_ss2pl.py)
- [ ] [`tests/database/test_in_memory_mode.py`](file:///workspace/arxiv-security-papers/tests/database/test_in_memory_mode.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `refactor/383-eliminate-full-tx-snapshot-and-unify-pager`

1. **差分ステージング方式への移行**:
   - `_exec_begin_tx` によるデータベース全体のディープコピーを廃止。
   - `TransactionManager` でトランザクション内で変更・追加・削除された行のみを記録（Write-Ahead / Delta Staging）し、ROLLBACK 時にその差分のみを取り消す軽量な巻き戻し機構を導入。
2. **Pager / SlottedPage ストレージとの結合**:
   - `TableCatalog` が `storage_engine="slotted"` または `storage_engine="pager"` を指定された場合に、`Pager` および `SlottedPage` レコード管理層に直接委譲できるファサードを拡充。
3. **トランザクションロールバックテストの検証**:
   - 変更があった行のみの巻き戻し、および未変更テーブルへの影響ゼロを保証する回帰テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `BEGIN TRANSACTION` 実行時の時間およびメモリ消費量が、テーブル内のレコード件数に関わらず $O(1)$ であること。
- [ ] ROLLBACK 時に変更された行のみが正確に復元されること。
- [ ] 既存のすべてのトランザクション・SAVEPOINT・ロールバックテストが 100% PASS すること。
- [ ] `make py_compile`, `make format`, `make static_analysis` が PASS すること。
