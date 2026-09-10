---
ID: 246
種別: Feature
優先度: Medium
ステータス: Open (New)
担当エージェント: Software Development (SWD) / Systems Architect / Database Specialist
---

# [FEAT/CORE] SkipList (スキップリスト) の共通コア実装と LSM MemTable および転置インデックス探索の高速化 (ID: 246)

## 1. 概要 / Summary

本リポジトリの設計書 [`docs/designs/DSN-05-storage_engine_internals.md`](../designs/DSN-05-storage_engine_internals.md) (7.2) では、LSM-Tree ストレージエンジンの MemTable についてロックフリー／並行 SkipList による順序付きメモリ構造を規定しているが、実態は単なる `dict` + `RLock` の簡易実装に留まっている。
また、[`docs/designs/DSN-04-search_engine_architecture.md`](../designs/DSN-04-search_engine_architecture.md) (2.2) においても、検索エンジンの転置インデックスポスティングリスト探索における SkipList 活用の設計が掲げられている。

本タスクでは、順序維持・範囲スキャン（Range Scan: `items_range(min_key, max_key)`）および $O(\log N)$ 探索を保証する **SkipList** を共通コア基盤 [`src/core/structures/skip_list.py`](../../src/core/structures/skip_list.py) にゼロ外部依存で実装し、LSM MemTable および検索ポスティング探索に適用して設計仕様を完全回収する。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-05-storage_engine_internals.md`](../designs/DSN-05-storage_engine_internals.md) (7.2 LSM MemTable)
  - [`docs/designs/DSN-04-search_engine_architecture.md`](../designs/DSN-04-search_engine_architecture.md) (2.2 Inverted Index Postings)
- **学術・技術参照**:
  - Pugh, W. (1990). "Skip Lists: A Probabilistic Alternative to Balanced Trees", *Communications of the ACM*.
- **規約**:
  - ゼロ外部依存（Python 3.14 Standard Library Only）
  - Xenon Rank A (CC <= 4), `mypy --strict` 準拠

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/core/structures/skip_list.py`](../../src/core/structures/skip_list.py) (新規):
  - `SkipListNode`, `SkipList`: 確率的レベル決定（$p=0.5$、最大レベル 16/32）、順序維持挿入・削除・検索、範囲イテレータ `range(start, end)`
- [ ] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `SkipList` のエクスポート
- [ ] [`src/database/lsm/memtable.py`](../../src/database/lsm/memtable.py):
  - `MemTable` の内部ソートバッファを `dict` から `SkipList` へ換装し、範囲スキャンとフラッシュソートの効率化
- [ ] [`src/search/core/index/postings.py`](../../src/search/core/index/postings.py):
  - ポスティングリストへのスキップポインタ探索の適用
- [ ] [`tests/core/test_skip_list.py`](../../tests/core/test_skip_list.py) (新規):
  - 単体テスト（挿入、探索、削除、重複キー更新、範囲スキャン、境界値）
- [ ] [`tests/database/lsm/test_lsm_tree.py`](../../tests/database/lsm/test_lsm_tree.py):
  - MemTable および LSM-Tree 全体回帰テストの 100% PASS

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/246-implement-skiplist-for-lsm-memtable-and-inverted-index`

1. `src/core/structures/skip_list.py` に `SkipList` クラスを実装。
2. API: `put(key, value)`, `get(key, default=None)`, `delete(key)`, `contains(key)`, `__len__()`, `range(min_key=None, max_key=None)`。
3. `src/database/lsm/memtable.py` の内部データバッファを SkipList に換装。
4. `tests/core/test_skip_list.py` による網羅的単体テストの作成。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/core/structures/skip_list.py` にゼロ外部依存で `SkipList` が実装されていること。
- [ ] `MemTable` が SkipList を用いて順序維持バッファリングを行い、既存の `items()` および範囲探索が正常に動作すること。
- [ ] `tests/core/test_skip_list.py` および既存 LSM テストが 100% PASS すること。
- [ ] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
