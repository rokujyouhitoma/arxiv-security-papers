---
ID: 042
種別: Feature
優先度: High
ステータス: Closed
完了日: 2026-08-20
---

# [FEAT] LSM-Tree ストレージエンジン（MemTable, SSTable, Sparse Index, Bloom Filter）の実装 (ID: 042)

## 1. 概要 / Summary

[DSN-14 次世代データベースエンジン設計書](../../designs/DSN-14-database_engine_architecture.md) マイルストーン 5（LSM-Tree Ingestion Engine & Bloom Filters）に基づき、時系列データ・論文メタデータの大量一括取り込み（Bulk Ingestion）および追記型ワークロードを極限まで高速化する **「LSM-Tree（Log-Structured Merge-Tree）ストレージエンジン」** をゼロ依存（Python 標準ライブラリ）で実装した。

インメモリ MemTable、不変ディスク SSTable（Sorted String Table）、疎インデックス（Sparse Index）、確率的 Bloom Filter、およびバックグラウンド Compaction（マージソート圧縮）を構築し、B+Tree と並ぶ高スループットな書き込み特化ストレージ基盤を確立した。

---

## 2. トレーサビリティ / Traceability

- 設計書: [DSN-14 次世代データベースエンジン包括的アーキテクチャ設計書](../../designs/DSN-14-database_engine_architecture.md)
  - 1.3 行指向ストレージ（OLTP）と列指向ストレージ（OLAP）
  - 15. 次世代実装ロードマップ マイルストーン 5 (LSM-Tree Ingestion Engine & Bloom Filters)
- 関連クローズド Issue:
  - [Issue 041: 2Q バッファプール（スキャン汚染防止）と Pin/Unpin ページライフサイクル管理の実装](closed/041-implement-2q-buffer-pool-and-page-pinning.md)
  - [Issue 040: MVCC（多版同時実行制御）と SS2PL ロックマネージャ・デッドロック検知の実装](closed/040-implement-mvcc-and-ss2pl-transaction-manager.md)
  - [Issue 039: 追記型永続WALファイルとARIESクラッシュリカバリマネージャの実装](closed/039-implement-disk-persistent-wal-and-aries-recovery.md)
  - [Issue 038: スロット化ページ（Slotted-Page）バイナリストレージエンジンの実装](closed/038-implement-slotted-page-binary-storage-engine.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/database/lsm/bloom_filter.py](../../src/database/lsm/bloom_filter.py) (新規: ゼロ依存 Bloom Filter、可変長ビット配列、多重ハッシュ関数)
- [x] [src/database/lsm/memtable.py](../../src/database/lsm/memtable.py) (新規: インメモリソート済バッファ、Tombstone 削除管理、容量閾値検知)
- [x] [src/database/lsm/sstable.py](../../src/database/lsm/sstable.py) (新規: 不変 SSTable バイナリファイル、Data Block、Sparse Index、CRC32 Footer)
- [x] [src/database/lsm/engine.py](../../src/database/lsm/engine.py) (新規: LSM-Tree 統合エンジン、多層 SSTable 探索、Leveled/Size-Tiered Compaction)
- [x] [src/database/lsm/__init__.py](../../src/database/lsm/__init__.py) (新規: LSM サブシステムエクスポート)
- [x] [src/database/__init__.py](../../src/database/__init__.py) (エクスポート更新: `LSMTreeEngine`, `BloomFilter`, `MemTable`, `SSTableReader`, `SSTableWriter`, `TOMBSTONE`)
- [x] [tests/database/test_lsm_tree.py](../../tests/database/test_lsm_tree.py) (新規: MemTable フラッシュ、SSTable 永続化、Bloom フィルタ偽陽性率、Compaction マージテスト)

---

## 4. 実装成果 / Implementation Results

Target Branch: `feat/042-lsm-tree-storage`

### 4.1 Bloom Filter (`src/database/lsm/bloom_filter.py`)
- **ハッシュ生成**: FNV-1a 64-bit と CRC32 を組み合わせた Kirsch-Mitzenmacher 二重ハッシュ技法により $K$ 個の独立ハッシュを生成。
- **ビット配列**: 可変長 `bytearray` による固定ビット幅管理。
- **偽陽性率**: False Negative 0%（100% 検出保証）、False Positive 率 $< 1\%$。
- **シリアライズ**: `to_bytes()`, `from_bytes()` による SSTable への直接バイナリ埋め込み。

### 4.2 MemTable (`src/database/lsm/memtable.py`)
- ソート順（昇順）を維持するインメモリデータ構造。
- `put(key, value)`, `delete(key)`（`TOMBSTONE` レコード追記）。
- `is_full()` による容量上限（デフォルト 64KB）監視と自動フラッシュ連携。

### 4.3 SSTable フォーマット (`src/database/lsm/sstable.py`)
- **バイナリ構造**:
  - **4KB Data Blocks**: `[KeyLen(2B), ValLen(2B), Key, Val]` の可変長レコード群。
  - **Sparse Index**: 各ブロックの先頭キー（`first_key`）とファイルオフセットを記録。二分探索（`bisect`）により $O(\log N)$ で対象ブロックを特定。
  - **Bloom Filter Block**: SSTable 内全キーの Bloom Filter バイナリ。
  - **Footer (32B)**: `IndexOffset(4B), IndexLen(4B), BloomOffset(4B), BloomLen(4B), Magic ("VDBSST01"), CRC32(4B)`。

### 4.4 LSM-Tree 統合エンジン & Compaction (`src/database/lsm/engine.py`)
- **階層探索パイプライン**:
  1. Active MemTable $\rightarrow$ 2. Immutable MemTables $\rightarrow$ 3. SSTables（最新順: Bloom フィルタ早期判定 $\rightarrow$ 疎インデックス二分探索 $\rightarrow$ データブロック）。
- **Compaction**:
  - 全 SSTable をマージソートし、最新レコードで上書き。
  - `TOMBSTONE`（削除マーク）を完全パージし、ディスク領域と読み取り効率を最適化。

---

## 5. 完了条件検証 (DoD Verification)

- [x] MemTable への高速追記と、容量超過時の自動 SSTable フラッシュが正常動作すること。
- [x] Bloom Filter により、存在しないキーに対する無駄なディスク I/O が 99% 削減されること（False Negative 0%、FP率 < 1%）。
- [x] 疎インデックス（Sparse Index）を用いた $O(\log N)$ 探索で SSTable から目的データが正確に取得できること。
- [x] Compaction により、複数 SSTable がマージされ、重複キーや削除済み Tombstone が正しくクリーンアップされること。
- [x] `make check_format`, `make py_compile`, `make static_analysis` がエラー 0 件ですべて PASS すること。
- [x] 新規テストスイート（`tests/database/test_lsm_tree.py`）が 100% PASS すること。
