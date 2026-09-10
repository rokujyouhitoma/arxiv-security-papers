---
ID: 243
種別: Feature / Performance
優先度: High
ステータス: Closed (Completed)
担当エージェント: Software Development (SWD) / Systems Architect
---

# [FEAT/SEARCH] src/search/platform/cache における FilterCache の Roaring Bitmap 換装とブーリアンフィルター演算の高速化 (ID: 243)

## 1. 概要 / Summary

検索エンジン基盤 `src/search/platform/cache/__init__.py` の `FilterCache(LRUCache[Set[int]])` およびハンドラー層 `src/search/platform/handler/__init__.py` において、フィルタークエリ（`fq`）でマッチした DocID 集合のキャッシュ・結合処理を Python `Set[int]` から [`src/core/structures/roaring_bitmap.py`](../../../src/core/structures/roaring_bitmap.py) の `RoaringBitmap` へ換装する。

Apache Solr の `BitDocSet` や Apache Lucene の `RoaringDocIdSet` と同様に、フィルター結果をビットマップ表現でキャッシュすることで、メモリ消費量を 1/5 以下に圧縮し、複数フィルター条件（`fq=cat:crypto AND fq=year:2026`）の交差判定・差分判定（AND / OR / NOT）を 64-bit ワード単位のビット演算（`combined_filter = combined_filter & fq_bitmap`）で超高速化する。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/241-migrate-roaring-bitmap-to-core-structures.md`](../241-migrate-roaring-bitmap-to-core-structures.md)
- **関連 Issue**: [`docs/issues/239-implement-roaring-bitmap-for-search-deletion-bitset.md`](../239-implement-roaring-bitmap-for-search-deletion-bitset.md), [`docs/issues/242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md`](../242-apply-roaring-bitmap-to-mvcc-transaction-snapshots.md)
- **設計書**: [`docs/designs/DSN-04-search_engine_architecture.md`](../../designs/DSN-04-search_engine_architecture.md)
- **業界参照**:
  - Apache Solr `DocSet` / `BitDocSet` アーキテクチャ
  - Apache Lucene `RoaringDocIdSet` フィルターキャッシュ

---

## 3. 脅威モデルとセキュリティ分析 (STRIDE / Threat Model)

| 脅威カテゴリ (STRIDE) | 潜在リスク | 緩和策・セキュリティ要件 |
| :--- | :--- | :--- |
| **Denial of Service (DoS)** | 複雑・多数の `fq` パラメータによる過度なフィルター生成とメモリ枯渇 | `LRUCache` の最大容量制約（デフォルト500件）と、`RoaringBitmap` のコンテナ圧縮（Array/Bitmap/Run）により、キャッシュメモリフットプリントを最小化。 |
| **Information Disclosure** | 削除済みドキュメント（Deleted Docs）がフィルター結果を通じて漏洩するリスク | `_match_doc_values` およびクエリ解決時に `segment.is_deleted(d_id)` チェックを厳格適用し、削除済み DocID をビットマップから除外。 |
| **Tampering** | キャッシュから返却された `RoaringBitmap` オブジェクトの外部書き換えによるキャッシュ汚染 | 複数 `fq` 合成時には `clone()` または新オブジェクトを生成する不変的・安全なブーリアン演算 (`&`, `|`) を用い、キャッシュ内部インスタンスの改変を防止。 |

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/core/structures/roaring_bitmap.py`](../../../src/core/structures/roaring_bitmap.py):
  - `RoaringBitmap.__eq__` の実装（他の `RoaringBitmap` または `Set[int]` との等価判定をサポート）
- [x] [`src/search/platform/cache/__init__.py`](../../../src/search/platform/cache/__init__.py):
  - `FilterCache(LRUCache[RoaringBitmap])` への型・実装換装
  - `FilterCache.put` における `Set[int]` / `Iterable[int]` の自動 `RoaringBitmap` 変換サポート（透過的互換性）
- [x] [`src/search/platform/handler/__init__.py`](../../../src/search/platform/handler/__init__.py):
  - `_resolve_single_fq(self, segment: Segment, fq_str: str) -> RoaringBitmap`
  - `_resolve_filter_ids(self, segment: Segment, fq_str: str) -> RoaringBitmap`
  - `_match_doc_values(self, segment: Segment, field: str, val: str) -> RoaringBitmap`
  - `_apply_filter_queries(self, segment: Segment, doc_scores: Dict[int, float], fq_list: Any) -> Dict[int, float]` の複数 `fq` ビット積 (`&`) 最適化
- [x] [`tests/search/platform/test_cache.py`](../../../tests/search/platform/test_cache.py):
  - `FilterCache` の `RoaringBitmap` キャッシュ動作、サイズ確認、等価性テストの追加・更新
- [x] [`tests/search/platform/test_handler.py`](../../../tests/search/platform/test_handler.py):
  - 複数 `fq` の合成、空フィルター、削除ドキュメント除外のテスト検証

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/243-apply-roaring-bitmap-to-search-filter-cache`

### Step 1: `RoaringBitmap.__eq__` の追加
- `src/core/structures/roaring_bitmap.py` に `__eq__` メソッドを追加し、別の `RoaringBitmap` または `Set[int]` と等価比較できるようにする。

### Step 2: `FilterCache` の RoaringBitmap 化
- `src/search/platform/cache/__init__.py` で `FilterCache` を `LRUCache[RoaringBitmap]` に更新。
- `put(self, key: str, value: Any) -> None` をオーバーライドし、渡された値が `set` や `list` の場合でも自動で `RoaringBitmap` に変換して安全に格納。

### Step 3: `SelectHandler` のフィルター処理最適化
- `_resolve_single_fq`, `_resolve_filter_ids`, `_match_doc_values` の返り値を `RoaringBitmap` に換装。
- `_apply_filter_queries` で、複数の `fq` を `combined_filter = combined_filter & fq_bitmap` で一括ビット積合成し、スコア辞書フィルタリングを 1 回のパスで完了させる。
- Xenon Rank A (循環的複雑度 CC <= 4) を維持するため、ヘルパー関数の分割を徹底。

### Step 4: テスト拡充と品質ゲートの検証
- `tests/search/platform/test_cache.py` に `RoaringBitmap` の型およびビット積の検証テストを追加。
- `pytest tests/search/` 全体（91件以上）の実行と全件 PASS 確認。
- `make check_format`、`xenon`、`mypy --strict` の完全クリア。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `RoaringBitmap.__eq__` が `RoaringBitmap` および `Set[int]` との等価比較を正しく判定できること。
- [x] `FilterCache` が内部で `RoaringBitmap` を保持し、`get()` で `Optional[RoaringBitmap]` が返却されること。
- [x] `SelectHandler` における単一・複数 `fq` の評価が `RoaringBitmap` のビット積演算によって正しく行われること。
- [x] 削除済みドキュメントがフィルター結果に含まれないこと。
- [x] 既存の検索機能テストおよびキャッシュテストが 100% PASS すること（リグレッション 0 件）。
- [x] Xenon Rank A (CC <= 4)、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。

