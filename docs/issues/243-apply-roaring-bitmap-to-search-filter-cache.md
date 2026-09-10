---
ID: 243
種別: Feature / Performance
優先度: High
ステータス: Open (New)
担当エージェント: Software Development (SWD) / Systems Architect
---

# [FEAT/SEARCH] src/search/platform/cache における FilterCache の Roaring Bitmap 換装とブーリアンフィルター演算の高速化 (ID: 243)

## 1. 概要 / Summary

検索エンジン基盤 `src/search/platform/cache/__init__.py` の `FilterCache(LRUCache[Set[int]])` およびハンドラー層 `src/search/platform/handler/__init__.py` において、フィルタークエリ（`fq`）でマッチした DocID 集合のキャッシュ・結合処理を Python `Set[int]` から [`src/core/structures/roaring_bitmap.py`](file:///workspace/arxiv-security-papers/src/core/structures/roaring_bitmap.py) の `RoaringBitmap` へ換装する。

Apache Solr の `BitDocSet` や Apache Lucene の `RoaringDocIdSet` と同様に、フィルター結果をビットマップ表現でキャッシュすることで、メモリ消費量を 1/5 以下に圧縮し、複数フィルター条件（`fq=cat:crypto AND fq=year:2026`）の交差判定・差分判定（AND / OR / NOT）を 64-bit ワード単位のビット演算で超高速化する。

---

## 2. トレーサビリティ / Traceability

- **前提 Issue**: [`docs/issues/241-migrate-roaring-bitmap-to-core-structures.md`](file:///workspace/arxiv-security-papers/docs/issues/241-migrate-roaring-bitmap-to-core-structures.md)
- **設計書**: [`docs/designs/DSN-04-search_engine_architecture.md`](file:///workspace/arxiv-security-papers/docs/designs/DSN-04-search_engine_architecture.md)
- **業界参照**:
  - Apache Solr `DocSet` / `BitDocSet` アーキテクチャ
  - Apache Lucene `RoaringDocIdSet` フィルターキャッシュ

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/search/platform/cache/__init__.py`](file:///workspace/arxiv-security-papers/src/search/platform/cache/__init__.py):
  - `FilterCache(LRUCache[RoaringBitmap])` への型・実装換装
- [ ] [`src/search/platform/handler/__init__.py`](file:///workspace/arxiv-security-papers/src/search/platform/handler/__init__.py):
  - `_resolve_single_fq`, `_resolve_filter_ids`, `_match_doc_values` の戻り値および結合を `RoaringBitmap` に換装
  - 複数 `fq` の交差（`&`）を RoaringBitmap 演算へ最適化
- [ ] [`tests/search/platform/test_cache.py`](file:///workspace/arxiv-security-papers/tests/search/platform/test_cache.py):
  - FilterCache の格納・取得・結合テストの更新
- [ ] [`tests/search/platform/test_handler.py`](file:///workspace/arxiv-security-papers/tests/search/platform/test_handler.py):
  - フィルタークエリ処理の正常性確認

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/243-apply-roaring-bitmap-to-search-filter-cache`

1. **FilterCache の換装**:
   - `class FilterCache(LRUCache[RoaringBitmap]):` として定義を更新。
2. **ハンドラー層のフィルター評価最適化**:
   - 単一 `fq` マッチ結果を `RoaringBitmap` で生成・キャッシュ。
   - 複数 `fq` の合成時: `combined_filter = combined_filter & fq_bitmap`（ビット積演算）。
   - クエリ結果（Postings List / 削除ビットセット）との交差: `live_docs - deleted_bitset & filter_bitset`。
3. **テスト検証**:
   - キャッシュヒット率、フィルター結合の正確性、リグレッション検証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `FilterCache` が `core.structures.roaring_bitmap.RoaringBitmap` を保持・管理すること。
- [ ] 複数 `fq` の論理演算が `RoaringBitmap` のビット演算で行われ、検索パフォーマンスが向上すること。
- [ ] 既存の全プラットフォーム・ハンドラーテストが PASS すること。
- [ ] Xenon Rank A、`mypy --strict` 0 エラー、フォーマッタ 100% 合格であること。
