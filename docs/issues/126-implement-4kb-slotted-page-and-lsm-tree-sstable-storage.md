---
ID: 126
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 固定長4KBバイナリスロットページ構造とLSM-Tree（MemTable/WAL/SSTable/Bloom Filter）ストレージエンジンの実装 (ID: 126)

## 1. 概要 / Summary
文献の定常的な収集、追記、再要約処理に伴うストレージ断片化とランダム I/O オーバーヘッドを抑制するため、固定長 4KB ページを基本単位とするバイナリスロットページ構造と、Log-Structured Merge-tree（LSM-Tree）書き込みパスを実装する。
WAL にトランザクションを逐次書き込みつつ MemTable をフラッシュし、Bloom フィルタを埋め込んだ不変 SSTable による高速な読み書き特性と耐クラッシュ性をゼロ外部依存で確立する。

---

## 2. トレーサビリティ / Traceability
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [src/database/storage/](../../src/database/storage/)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/database/storage/slotted_page.py`
- [ ] `src/database/storage/lsm_tree.py`
- [ ] `src/database/storage/sstable.py`
- [ ] `src/database/storage/bloom_filter.py`
- [ ] `tests/database/storage/test_slotted_page.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/126-implement-4kb-slotted-page-and-lsm-tree-sstable-storage`
1. 4KB 固定長スロットページレイアウト（ヘッダ、スロットオフセット配列、タプル末尾格納）。
2. インメモリ MemTable（AVL/Red-Black/SkipList）とシーケンシャル SSTable 書き出し。
3. SSTable ごとの Bloom フィルタによる存在しないキーのディスクシーク $O(1)$ スキップ。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 4KB ページ構造での断片化のない可変長レコード読み書きができること
- [ ] SSTable フラッシュおよび Bloom フィルタによる高速ルックアップが機能すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
