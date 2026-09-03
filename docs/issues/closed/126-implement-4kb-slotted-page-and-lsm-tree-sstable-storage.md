---
ID: 126
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 固定長4KBバイナリスロットページ構造とLSM-Tree（MemTable/WAL/SSTable/Bloom Filter）ストレージエンジンの実装 (ID: 126)

## 1. 概要 / Summary
大量の論文メタデータ、要約、ベクトルインデックスの定常的な追記・更新・再要約処理において、OS ファイルシステム上のストレージ断片化とランダム I/O オーバーヘッドを徹底抑制するため、固定長 4KB（4096 バイト）ページを基本単位とするバイナリスロットページ構造と、Log-Structured Merge-tree（LSM-Tree）書き込みパスを完全統合する。

先行書き込みログ（WAL: Write-Ahead Log）にトランザクションをシーケンシャル追記しながらインメモリ MemTable（AVL/SkipList）へ即時反映し、容量閾値超過時に不変 4KB スロットブロック群からなる SSTable へとアトミックにフラッシュする。SSTable フッターには Bloom フィルタおよびスパースインデックスを埋め込み、存在しないキーに対する無駄なディスクシークを $O(1)$ でスキップする高スループット・耐クラッシュストレージエンジンを Pure Python（ゼロ外部依存）で確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-OPS-01, UC-OPS-02)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 042: 4KB スロッテッドページ・B+Tree・2Q バッファプールのゼロ外部依存実装](closed/042-implement-slotted-page-btree-and-buffer-pool.md)
- [Issue 046: LSM-Tree ストレージエンジン（MemTable・SSTable・Bloom Filter・コンパクション）の実装](closed/046-implement-lsm-tree-storage-engine.md)
- [src/database/storage/slotted_page.py](../../src/database/storage/slotted_page.py)
- [src/database/lsm/engine.py](../../src/database/lsm/engine.py)
- [src/database/lsm/sstable.py](../../src/database/lsm/sstable.py)
- [src/database/lsm/memtable.py](../../src/database/lsm/memtable.py)
- [src/database/lsm/bloom_filter.py](../../src/database/lsm/bloom_filter.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-126-01: プロセス急停止・クラッシュ時の WAL 不整合およびデータ破壊 (Crash Inconsistency)**
  - *脅威*: MemTable フラッシュ中や WAL 書き込み途中に SIGKILL や電源断が発生し、次回起動時に破損バイト列を読み込んで起動不能となる。
  - *対策*: WAL レコードおよび 4KB ページヘッダに CRC32 チェックサムを埋め込み、リカバリ走査時に破損以降の不完全フレームを破棄して直前の一貫したスナップショットまで安全にロールフォワード復旧。
- **T-126-02: 単一キー・バリューの極大化による 4KB ページ境界オーバーフロー (Page Overflow DoS)**
  - *脅威*: 4096 バイトを超える巨大な生論文テキストや埋め込みデータが単一スロットに書き込まれ、ページメモリ構造が破壊される。
  - *対策*: `PAGE_SIZE = 4096` を超えるレコードに対してはオーバーフローページフラグ（`PageType.OVERFLOW`）およびリンクリスト構造を適用し、スロット内には先頭ポインタとオフセットのみを格納する厳格境界チェックを導入。
- **T-126-03: コンパクション過負荷による一時ディスク容量枯渇 (Disk Exhaustion)**
  - *脅威*: 複数 SSTable のマージコンパクション中に一時ファイルが重複生成され、ディスク空き容量を使い果たしてシステム全体が停止する。
  - *対策*: テンポラリファイルの作成（`.tmp.sstable`）と完了後のアトミックリネーム（`os.replace`）を行い、ディスク空き容量の事前チェック（最低 2 倍のワークスペース確保）を義務付け。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/database/storage/slotted_page.py` (4KB バイナリレイアウト、CRC32 チェックサム、スロット配列管理)
- [x] `src/database/lsm/engine.py` (MemTable, WAL, SSTable, コンパクションのオーケストレーション)
- [x] `src/database/lsm/sstable.py` (4KB スロットブロック化、スパースインデックス、Bloom フィルタ統合)
- [x] `src/database/lsm/memtable.py` (インメモリ AVL/SkipList 木構造とメモリ閾値監視)
- [x] `src/database/lsm/bloom_filter.py` (FNV-1a / Murmur 風ハッシュによる多段ビット配列)
- [x] `tests/database/storage/test_slotted_page_lsm.py` (LSM-Tree E2E クラッシュリカバリ、ポイントルックアップ、コンパクション検証)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/126-implement-4kb-slotted-page-and-lsm-tree-sstable-storage`

1. **ステップ 1: 4KB スロットページのバイナリレイアウト確立 (`src/database/storage/slotted_page.py`)**:
   - ヘッダフォーマット `<IQHHHHI` (28 バイト: PageID, LSN, SlotCount, FreeLower, FreeUpper, Flags, NextPageID + CRC32)。
   - スロットオフセット配列（ヘッダ直後から下向き成長）とタプルデータ領域（ページ末尾から上向き成長）の厳格な空き領域（Free Space）計算。
   - レコード削除時のデフラグメンテーション（VACUUM）関数 `compact_page()` を実装。
2. **ステップ 2: SSTable の 4KB スロットブロック化 (`src/database/lsm/sstable.py`)**:
   - SSTable の各データブロックを独立した 4096 バイトのスロットページとして直列化。
   - 各ブロックの先頭キー（First Key）を収集してファイル末尾にスパースインデックスを配置。
   - `BloomFilter`（偽陽性率 1% 以下）をシリアライズして SSTable フッターに埋め込み、存在しないキーのルックアップをディスクシークなしで即時遮断。
3. **ステップ 3: MemTable と WAL の書き込みパス統合 (`src/database/lsm/engine.py`)**:
   - `put(key, value)` 呼び出し時に、WAL へのログ先行書き込み（`struct.pack` 形式の追記）と `active_memtable` へのタプル格納を実行。
   - メモリ上限（デフォルト 64KB または設定値）到達時に `active_memtable` を `immutable_memtables` へ移管し、バックグラウンドスレッドまたは同期待ち合わせで SSTable へフラッシュ。
4. **ステップ 4: クラッシュリカバリとコンパクション**:
   - エンジン起動時に `wal.log` を走査し、未フラッシュのトランザクションを MemTable へリプレイ。
   - SSTable 本数が閾値（例: 4本）を超えた場合に、マルチウェイマージ（K-way Merge）による重複キー・Tombstone（削除マーカー）除去コンパクションを実行。
5. **ステップ 5: 品質検証とストレステスト**:
   - `tests/database/storage/test_slotted_page_lsm.py` を整備。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 4KB 固定長スロットページ構造で可変長レコードの書き込み・読み出し・削除が断片化なく動作すること
- [x] 破損データが注入された際に `PageCorruptionError` が発生し、正常データへの伝播が防止されること
- [x] SSTable に埋め込まれた Bloom フィルタにより、存在しないキーに対する無駄なブロック読み込みが遮断されること
- [x] WAL リプレイによる予期せぬシャットダウンからの最新コミット状態リカバリが成功すること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
