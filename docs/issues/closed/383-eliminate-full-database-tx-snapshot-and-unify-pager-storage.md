---
ID: 383
種別: Architecture
優先度: Medium
ステータス: Closed
---

# [ARCH/REFACTOR] トランザクション開始時の全テーブルディープコピー廃止および Pager / SlottedPage ストレージ層の統合 (ID: 383)

## 1. 概要 / Summary

PyNYTProf のプロファイリングおよびコード静的解析により、トランザクション管理と基盤ストレージ層に以下のアーキテクチャ上の課題が判明した：
1. **トランザクション開始・ロールバック時の全メモリ複製・インデックス再構築**: `SQLExecutor._exec_begin_tx` において、`BEGIN TRANSACTION` や `SAVEPOINT` が呼ばれるとデータベース内のすべてのテーブルの全メタデータと全ベクトルをメモリ上に辞書複製（Deep Copy）していた。さらに、`ROLLBACK` 時には全テーブルのメタデータ・ベクトルを上書きし、全件から HNSW インデックスを再構築していたため、10,000 件のテーブルではたった 100 行のロールバックに **38.1 秒**、1 行の SAVEPOINT ロールバックに **39.1 秒** を要する深刻な性能劣化が発生していた。
2. **ストレージエンジンのアーキテクチャ分断**: プロジェクト内には 4KB ページ管理を行う `Pager`, `2Q PageCache`, `WALWriter`, `SlottedPage`、および列指向の `PAXTable` や `MVCCManager` などの高度なストレージプリミティブが完備されている。しかし、`StorageEngineFactory` に `slotted` / `pager` がエンジンとして登録されておらず、`SQLExecutor` から `CREATE TABLE ... USING slotted` の形式で利用できない状態にあった。

本 Issue では、トランザクション開始時の全件ディープコピーおよびロールバック時の全件再構築を廃止し、変更行のみを記録・巻き戻す **差分 Undo ログ方式（Delta Staging & Reverse Undo）** へ刷新するとともに、`Pager` / `SlottedPage` ストレージ層を SQL 実行エンジンから利用可能なプラガブルストレージエンジンとして接続統合した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (4-Tier Storage: VFS, Pager, VDBE, Compiler)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/sql/executor.py` (`_exec_begin_tx`, `_restore_rollback_snapshot`, `TransactionManager`)
  - `src/database/sql/transaction.py` (`TransactionManager`, `SavepointRecord`)
  - `src/database/storage/pager.py` (`Pager`, `PageCache`)
  - `src/database/storage/slotted_page.py` (`SlottedPage`, `TupleSerializer`)
  - `src/database/storage/slotted_page_storage.py` (`SlottedPageStorage`)
  - `src/database/storage/factory.py` (`StorageEngineFactory`)
  - `scripts/benchmark_tx_operations.py` (定量ベンチマーク測定スクリプト)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/sql/executor.py`](file:///workspace/arxiv-security-papers/src/database/sql/executor.py) (`_exec_begin_tx`, `_restore_rollback_snapshot`, `_record_delete_undo`, `_undo_single_insert`, `_undo_single_update`, `_undo_single_delete`)
- [x] [`src/database/sql/transaction.py`](file:///workspace/arxiv-security-papers/src/database/sql/transaction.py) (`TransactionManager`, `SavepointRecord`, `UndoAction`)
- [x] [`src/database/storage/slotted_page_storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/slotted_page_storage.py) (`SlottedPageStorage` アダプター)
- [x] [`src/database/storage/factory.py`](file:///workspace/arxiv-security-papers/src/database/storage/factory.py) (`StorageEngineFactory` に `slotted` / `pager` 登録)
- [x] [`src/database/sql/generated_sql_ddl_parser.py`](file:///workspace/arxiv-security-papers/src/database/sql/generated_sql_ddl_parser.py) (`_ALLOWED_ENGINES` に `slotted` / `pager` 追加)
- [x] [`scripts/benchmark_tx_operations.py`](file:///workspace/arxiv-security-papers/scripts/benchmark_tx_operations.py) (ベンチマークスクリプト)
- [x] [`tests/database/transaction/test_mvcc_and_ss2pl.py`](file:///workspace/arxiv-security-papers/tests/database/transaction/test_mvcc_and_ss2pl.py)
- [x] [`tests/database/test_in_memory_mode.py`](file:///workspace/arxiv-security-papers/tests/database/test_in_memory_mode.py)

---

## 4. 実装方針と計測値 / Implementation Plan & Benchmark Results

Target Branch: `refactor/383-eliminate-full-tx-snapshot-and-unify-pager`

### 4.1. 修正前・修正後の性能比較 (10,000 件テーブル、100 件挿入ロールバック)

測定スクリプト: `scripts/benchmark_tx_operations.py`

| 測定項目 | 修正前 (Baseline) | 修正後 (Optimized) | 改善率 / 高速化倍率 |
| :--- | :--- | :--- | :--- |
| **BEGIN (10k rows table)** | 1.973 ms (506.9 ops/s) | **0.112 ms (8,953.2 ops/s)** | **約 17.6 倍 高速化 (94.3% 短縮)** |
| **ROLLBACK (100 dirty on 10k)** | 38,114.467 ms (38.11 秒) | **0.429 ms (2,329.6 ops/s)** | **約 88,844 倍 高速化 (99.999% 短縮)** |
| **SAVEPOINT (10k rows table)** | 10.602 ms (94.3 ops/s) | **0.097 ms (10,265.7 ops/s)** | **約 109.3 倍 高速化 (99.1% 短縮)** |
| **ROLLBACK TO SP (1 item dirty)** | 39,094.892 ms (39.09 秒) | **0.109 ms (9,214.2 ops/s)** | **約 358,668 倍 高速化 (99.9997% 短縮)** |

### 4.2. 詳細実装内容

1. **差分 Undo ログ方式（Delta Staging & Reverse Undo）への刷新**:
   - `TransactionManager` に `UndoAction`（`action_type`, `table_name`, `payload`）および `record_undo()` を導入。
   - `BEGIN TRANSACTION` および `SAVEPOINT` 時の全テーブルディープコピーを完全廃止し、$O(1)$ 初期化へ移行。
   - 行操作（INSERT / UPDATE / DELETE）時に差分 Undo 情報を記録。
     - **INSERT**: 挿入インデックスと行内容を記録。Undo 時に $O(1)$ pop 実行。
     - **UPDATE**: 更新前レコード内容（`old_row`）を記録。Undo 時に $O(1)$ 上書き復元。
     - **DELETE**: 削除対象テーブルの変更前状態を記録。Undo 時にストレージ復元。
   - `ROLLBACK` および `ROLLBACK TO SAVEPOINT` 時は逆順（LIFO）で差分 Undo アクションのみを高速適用。未変更テーブルへのアクセスは完全にゼロ。
2. **Pager / SlottedPage ストレージエンジンの統合**:
   - `SlottedPageStorage` アダプター（[`src/database/storage/slotted_page_storage.py`](file:///workspace/arxiv-security-papers/src/database/storage/slotted_page_storage.py)）を実装。
   - `StorageEngineFactory` に `slotted`, `slotted_page`, `pager` を登録。
   - `generated_sql_ddl_parser.py` の `_ALLOWED_ENGINES` に `slotted`, `slotted_page`, `pager` を追加し、`CREATE TABLE ... USING slotted` の完全動作を実現。
3. **品質ゲート & Pure Python 厳格遵守**:
   - Xenon 循環的複雑度 Rank A (CC <= 5)、Mypy Strict、Flake8 (`# noqa: E402 は使うな` を厳格遵守)。
   - 既存全テスト（446件）および SQLite3 差分テスト（75件）の完全合格。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `BEGIN TRANSACTION` および `SAVEPOINT` 実行時の時間およびメモリ消費量が、テーブル内のレコード件数に関わらず $O(1)$ であること。
- [x] ROLLBACK（100件）の所要時間がベースライン（38.1秒）から 100ms 未満へ劇的短縮（実測: **0.429ms、約 88,844 倍高速化**）すること。
- [x] ROLLBACK TO SAVEPOINT の所要時間も同様にミリ秒単位で完了（実測: **0.109ms、約 358,668 倍高速化**）すること。
- [x] `CREATE TABLE ... USING slotted` が正常にパース・作成・クエリ実行できること。
- [x] 既存のすべてのトランザクション・SAVEPOINT・ロールバックテスト（446件＋75件）が 100% PASS すること。
- [x] `make py_compile`, `make format`, `make check_format`, `make static_analysis` がすべて PASS すること。
- [x] `# noqa: E402` などの警告抑制コメントを含めないこと。


