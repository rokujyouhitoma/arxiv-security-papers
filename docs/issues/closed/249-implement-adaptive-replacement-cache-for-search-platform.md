---
ID: 249
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
担当エージェント: Software Development (SWD) / Systems Architect / Application Specialist (APS)
---

# [FEAT/CORE] Adaptive Replacement Cache (ARC) の共通コア実装と検索プラットフォーム・キャッシュ自己適応化 (ID: 249)

## 1. 概要 / Summary

本リポジトリの検索プラットフォーム層 [`src/search/platform/cache/`](../../src/search/platform/cache/) では、クエリキャッシュやフィルターキャッシュに単純な `LRUCache` が利用されている。

データベースのバッファプール層（[`src/database/storage/buffer_pool.py`](../../src/database/storage/buffer_pool.py)）では走査耐性（Scan Resistance）の高い 2Q アルゴリズムが導入されているのに対し、検索キャッシュ層は LRU 止まりであり、大規模な一括検索や全件バッチ走査が行われた際に有用なキャッシュが追い出される「キャッシュ汚染」が発生しやすい。

本タスクでは、最新性（Recency: $T_1, B_1$）と頻度（Frequency: $T_2, B_2$）の 2 組の二重双方向リンクリストを持ち、ワークロードの変動に応じて目標サイズ $p$ を自己調整（Self-Tuning）する **Adaptive Replacement Cache (ARC)** を共通コア基盤 [`src/core/structures/arc_cache.py`](../../src/core/structures/arc_cache.py) に実装する。
これにより、検索クエリキャッシュのヒット率（Hit Ratio）を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability

- **設計書**:
  - [`docs/designs/DSN-04-search_engine_architecture.md`](../designs/DSN-04-search_engine_architecture.md) (Search Cache Architecture)
- **学術・技術参照**:
  - Megiddo, N., & Modha, D. S. (2003). "ARC: A Self-Tuning, Low Overhead Replacement Cache", *USENIX Conference on File and Storage Technologies (FAST '03)*.
- **規約**:
  - ゼロ外部依存（Standard Library Only）
  - Xenon Rank A (CC <= 4), `mypy --strict` 準拠

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/arc_cache.py`](../../src/core/structures/arc_cache.py) (新規):
  - `ARCCache[K, V]`: $T_1$ (最新ヒット), $T_2$ (頻出ヒット), $B_1$ (最新ゴースト), $B_2$ (頻出ゴースト)、自己調整パラメータ $p$、`get(key)`, `put(key, value)`, `evict()`, `hit_ratio()`
- [x] [`src/core/structures/__init__.py`](../../src/core/structures/__init__.py):
  - `ARCCache` のエクスポート
- [x] [`src/search/platform/cache/__init__.py`](../../src/search/platform/cache/__init__.py):
  - `ARCCacheAdapter`, `ARCFilterCache`, `SolrCache(use_arc=...)` によるプラグイン換装対応
- [x] [`tests/core/test_arc_cache.py`](../../tests/core/test_arc_cache.py) (新規):
  - 基本キャッシュ操作、ゴーストキャッシュによる $p$ の動的適応、走査耐性（Scan Resistance）テスト
- [x] [`tests/search/platform/test_cache.py`](../../tests/search/platform/test_cache.py):
  - 検索キャッシュ層での結合回帰テスト

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/249-implement-adaptive-replacement-cache-for-search-platform`

1. `src/core/structures/arc_cache.py` に `ARCCache[K, V]` を実装。
2. 双方向連結リストノードまたは OrderedDict を用いて $T_1, T_2, B_1, B_2$ を効率的に管理。
3. ゴーストキャッシュ（$B_1, B_2$）ヒット時の学習パラメータ $p$ 増減アルゴリズムを忠実に再現。
4. 単体テスト作成および品質ゲート（Xenon Rank A, mypy）の検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/core/structures/arc_cache.py` に `ARCCache` が実装されていること。
- [x] 大量の一度きりのキー走査（Scan ワークロード）に対して頻出キー（Frequency）が保護されること。
- [x] `tests/core/test_arc_cache.py` が新規作成され、100% PASS すること。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
