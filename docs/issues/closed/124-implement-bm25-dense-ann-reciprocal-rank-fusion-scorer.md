---
ID: 124
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] BM25語彙検索とDense ANN意味検索を統合するRRF（相互順位融合）ハイブリッドスコアラーおよびベクトルストレージ・ビルドパイプラインの実装 (ID: 124)

## 1. 概要 / Summary
非有界な BM25 スコア体系と有界なコサイン類似度スコアの線形結合に伴うスケール不整合・極端値バイアスを排除するため、相互順位融合（Reciprocal Rank Fusion: RRF, 式 $RRF(d) = \sum_{m} \frac{1}{k + r_m(d)}$）を導入し、語彙検索（BM25）と意味的ベクトル検索（Dense ANN）の完全融合パイプラインを確立する。
同時に、未生成となっていたバイナリベクトルストレージ（`outputs/vector_db/vectors.vdb`）および HNSW インデックス（`outputs/vector_db/hnsw_index.json`）のビルドコマンド（`make build_vector_db`）の実装、`README.md` クイックスタートへの反映、およびセマンティッククエリキャッシュ（`QuerySemanticCache`）における検索件数固定化バグを根本解決する。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [README.md](../../README.md)
- [src/search/vector/hybrid.py](../../src/search/vector/hybrid.py)
- [src/search/vector_engine.py](../../src/search/vector_engine.py)
- [src/search/query/query_cache.py](../../src/search/query/query_cache.py)
- [src/mcp/papers_server.py](../../src/mcp/papers_server.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/search/vector_engine.py`
- [x] `src/search/vector/hybrid.py`
- [x] `src/search/query/query_cache.py`
- [x] `src/mcp/papers_server.py`
- [x] `README.md`
- [x] `tests/search/test_vector_engine.py`
- [x] `tests/search/test_rrf_hybrid.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/124-implement-bm25-dense-ann-reciprocal-rank-fusion-scorer`

1. **ベクトルストレージ・ビルド機能の拡張 (`src/search/vector_engine.py`)**:
   - `build_vector_storage()` / `build_index()` にて、全 OKF 論文から `DeterministicEmbedding` による Float32 ベクトル（128次元）を生成し、`outputs/vector_db/vectors.vdb` および `hnsw_index.json` へ書き出す。
   - `load_index()` 時に既存の `vectors.vdb` および `hnsw_index.json` をロードし、`search_vector_ann()` が即座にサブミリ秒で近傍類似論文 Top-K を返却できるようにする。
2. **`README.md` クイックスタートへのビルドコマンド追記**:
   - 「6. クイックスタート (Quick Start)」のインテリジェンス・検索準備セクションに `make build_vector_db`（`python -m search.vector_engine --build`）を明記。
3. **セマンティッククエリキャッシュの件数固定化バグ修正 (`src/search/vector_engine.py`, `src/search/query/query_cache.py`)**:
   - キャッシュ結果の件数 `len(cached_res)` が要求された `top_k` より少なく、かつ `has_more=True` の場合はキャッシュミスと判定して再検索を実行する。
4. **Dense + Sparse ハイブリッド候補生成 (`retrieve_candidates`)**:
   - 語彙転置インデックスからの候補に加え、ベクトル ANN 探索（`search_vector_ann`）の上位候補を候補集合へマージし、語彙不一致でも意味が近い論文を確実に拾い上げる。
5. **RRF スコアラー連携 & スコアスケール平準化**:
   - `search_rrf_hybrid()` で BM25 と Dense ANN の順位を滑らかに融合し、Top-K を返却。
6. **品質ゲート検証**:
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `make build_vector_db` により `vectors.vdb` および `hnsw_index.json` が正常に生成・永続化されること
- [x] `search_vector_ann()` が空配列 `[]` ではなく、関連する論文 Top-K を即座に返却すること
- [x] `README.md` の「6. クイックスタート」にビルドコマンドが明確に記載されていること
- [x] `top_k=2` 実行後に `top_k=20` で検索した際、正常に 20 件の結果が返却されること（キャッシュ件数固定化バグの解消）
- [x] 語彙一致と意味類似度の順位が RRF により安定的に融合されること
- [x] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること

