---
ID: 043
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] CoW (Copy-on-Write) B-Tree & mmap ゼロコピーリードエンジンの実装 (ID: 043)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) 第6.2節（LMDBとゼロコピー）およびマイルストーン 4（LMDB-style Zero-Copy & CoW Architecture）に基づき、OS の `mmap` 仮想記憶を活用した **「ゼロコピー読み取り（Zero-Copy Read）」** と、シャドウページングによる **「CoW (Copy-on-Write) B-Tree ストレージエンジン」** を `src/database/cow/` に実装した。

変更ノードのパスのみを複製して新規ページへ書き出すシャドウページングと、メタページ（Meta Page 0/1）の Ping-Pong アトミック切り替えにより、WAL レスでの ACID 耐久性と、リーダーが一切ロックを獲得しない完全ロックフリー SWMR（Single-Writer Multi-Reader）MVCC を確立した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 1.2 メモリベース DBMS vs ディスクベース DBMS (mmap ゼロコピー)
  - 6.2 LMDB（Lightning Memory-Mapped Database）とゼロコピー
  - 6.2.1 OS メモリマップ（`mmap`）による完全ゼロコピー
  - 6.2.2 単一ライター・複数リーダー（SWMR）と MVCC
  - 15. 次世代実装ロードマップ マイルストーン 4
- 関連クローズド Issue:
  - [Issue 042: LSM-Tree ストレージエンジン（MemTable, SSTable, Sparse Index, Bloom Filter）の実装](closed/042-implement-lsm-tree-storage-engine-and-bloom-filter.md)
  - [Issue 041: 2Q バッファプール（スキャン汚染防止）と Pin/Unpin ページライフサイクル管理の実装](closed/041-implement-2q-buffer-pool-and-page-pinning.md)
  - [Issue 040: MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装](closed/040-implement-mvcc-and-ss2pl-transaction-manager.md)
  - [Issue 039: 追記型永続WALファイルとARIESクラッシュリカバリマネージャの実装](closed/039-implement-disk-persistent-wal-and-aries-recovery.md)
  - [Issue 038: スロット化ページ（Slotted-Page）バイナリストレージエンジンの実装](closed/038-implement-slotted-page-binary-storage-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/cow/mmap_file.py](../../src/database/cow/mmap_file.py) (新規: OS mmap ゼロコピー抽象化、memoryview スライス、4KB ページアロケータ)
- [x] [src/database/cow/meta_page.py](../../src/database/cow/meta_page.py) (新規: Double Meta Page Ping-Pong 管理、アトミックコミット、CRC32)
- [x] [src/database/cow/cow_btree.py](../../src/database/cow/cow_btree.py) (新規: Copy-on-Write B-Tree、シャドウページング、不変ノード走査、フリーリスト管理)
- [x] [src/database/cow/engine.py](../../src/database/cow/engine.py) (新規: SWMR トランザクションエンジン、ReadTransaction (Lock-Free), WriteTransaction)
- [x] [src/database/cow/__init__.py](../../src/database/cow/__init__.py) (新規: CoW サブシステムエクスポート)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新: `CoWEngine`, `CoWBTree`, `CoWNode`, `CoWReadTx`, `CoWWriteTx`, `MetaPage`, `MMapFile`)
- [x] [tests/database/test_cow_btree.py](../../tests/database/test_cow_btree.py) (新規: mmap ゼロコピーテスト、CoW シャドウページング整合性、SWMR ロックフリー並行テスト、クラッシュ一貫性テスト)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/043-cow-btree-mmap`

### 4.1 `mmap` ゼロコピーファイル (`src/database/cow/mmap_file.py`)
- **仮想記憶マッピング**: 16MB（4096 ページ）の仮想メモリ空間を事前予約し、`mmap.mmap()` による高速ゼロコピーアクセスを提供。
- **`read_page_view(page_id)`**: `memoryview` スライスにより、Python のヒープアロケーションオーバーヘッドを完全に排除。

### 4.2 Meta Page Ping-Pong (`src/database/cow/meta_page.py`)
- **Double Meta Page**: Page 0 と Page 1 を 2 面のメタページ（Meta A / Meta B）として確保。
- **アトミックコミット**: コミット時は交代面（`tx_id % 2`）に `tx_id`, `root_page_id`, `page_count` を書き込み、`msync`/`flush` で同期。
- **CRC32 検証**: 電源喪失やクラッシュ時でも、最新かつチェックサムが正常なメタ面を自動ロード。

### 4.3 Copy-on-Write (CoW) B-Tree (`src/database/cow/cow_btree.py`)
- **シャドウページング**: 既存ページを一切上書きせず、変更対象リーフからルートまでの全祖先ノードを新規割り当てしてツリーを再構築。
- **ロックフリー検索**: 不変ページ構造により、読み取りトランザクションは一切のロック・ラッチを獲得せずに高速走査可能。

### 4.4 SWMR トランザクションエンジン (`src/database/cow/engine.py`)
- **`begin_read() -> CoWReadTx`**: 現在の Meta Page スナップショットを参照し、完全ロックフリーで並行実行。
- **`begin_write() -> CoWWriteTx`**: 単一ライターミューテックスにより直列化。`commit()` で Meta Page を Ping-Pong 切り替え、`rollback()` で変更ページを安全に破棄。

---

## 5. 完了条件検証 (DoD Verification)

- [x] `mmap` による 4KB ページのゼロコピー読み取りが正常に動作すること。
- [x] CoW シャドウページングにより、更新中も既存リーダーが旧バージョンのスナップショットを一貫して読み取れること（SWMR ロックフリー MVCC）。
- [x] Meta Page の Ping-Pong 切り替えにより、WAL なしでアトミックコミットが保証されること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_cow_btree.py`）が 100% PASS すること。
