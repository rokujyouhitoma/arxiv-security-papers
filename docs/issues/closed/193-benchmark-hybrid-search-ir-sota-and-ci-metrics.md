---
ID: 193
種別: Feature / Benchmark
優先度: High
ステータス: Closed
Created At: 2026-09-06T18:28:00+09:00
Closed At: 2026-09-06T18:48:00+09:00
---

# [FEAT/BENCHMARK] IR標準ベンチマーク（BEIR / CTI-Bench）によるハイブリッド探索（BM25+HNSW+Graph）の定量的SOTA性能立証とCI計測基盤の実装 (ID: 193)

## 1. 概要 / Summary

本リポジトリで独自開発された Pure Python 検索エンジン（BM25 転置インデックス + HNSW ベクトル近傍探索 + Dual CSR 知識グラフ伝播によるハイブリッド探索エンジン）について、「自作エンジンは遅くて精度が低いのではないか」という懸念を客観的に払拭し、産業標準（Lucene / Elasticsearch、Chroma / Qdrant、FAISS）に匹敵・凌駕する性能を持つことを工学的・定量的に証明する。

情報検索（IR: Information Retrieval）の標準ベンチマーク体系である **BEIR（Benchmarking Information Retrieval）** の学術データセット（SciFact / NFCorpus 等）およびセキュリティドメイン特化ベンチマーク（**SecEval / CTI-Bench**）を用い、検索品質（`NDCG@10`, `Recall@K`, `MAP`, `MRR`）とシステム効率（`QPS`, `p95/p99 レイテンシ`, `メモリ消費量 (RSS)`）を CI で自動計測・比較検証する基盤を構築する。

---

## 2. トレーサビリティ / Traceability
- 参照基準: BEIR (Benchmarking Information Retrieval, NeurIPS 2021)
- 検索エンジン実装: `src/search/engine/`, `src/search/eval/`, `src/graph/citation_graphrag.py`
- ドメインタクソノミー: MITRE ATT&CK, NIST SP 800-53, CVE/CWE

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/search/eval/sota_runner.py](../../src/search/eval/sota_runner.py) (新規作成: SOTA 比較ベンチマークランナー)
- [x] [src/search/eval/dataset.py](../../src/search/eval/dataset.py) (BEIR / CTI-Bench データセット形式のローダー・合成評価セット生成)
- [x] [src/search/eval/metrics.py](../../src/search/eval/metrics.py) (レイテンシパーセンタイル、QPS、スループット、メモリ RSS プロファイラ追加)
- [x] [tests/search/eval/test_sota_runner.py](../../tests/search/eval/test_sota_runner.py) (新規作成: SOTA ランナー単体テスト)
- [x] [docs/benchmarks/sota_evaluation.md](../../docs/benchmarks/sota_evaluation.md) (新規作成: 客観的 SOTA 比較公開レポート)
- [x] [Makefile](../../Makefile) (`make benchmark_ir` ターゲット追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/193-benchmark-hybrid-search-ir-sota-and-ci-metrics`

1. **データセット & 合成評価セット生成基盤の拡張 (`src/search/eval/dataset.py`)**:
   - `BEIRDataset`: `corpus` (dict of doc_id -> text/metadata), `queries` (dict of query_id -> text), `qrels` (dict of query_id -> {doc_id: relevance_score}) を表現するクラス。
   - `generate_cti_bench_dataset(num_docs=100, num_queries=20)`: 決定論的かつ再現可能なセキュリティ特化データセット（MITRE ATT&CK、CVE、零日攻撃、ポスト量子暗号等のクエリおよび正解適合文書集合）の自動生成機能。
2. **多角プロファイリングと指標算出 (`src/search/eval/metrics.py`)**:
   - `PerformanceMetrics`: `qps`, `latency_p50_ms`, `latency_p95_ms`, `latency_p99_ms`, `avg_latency_ms`, `memory_rss_mb`。
   - `profile_search_execution(search_fn, queries, top_k=10, warmup=3)`: 複数回反復測定による正確なパーセンタイルとスループットの算出。
3. **比較対照（Baselines）と自作ハイブリッド探索の統合ランナー (`src/search/eval/sota_runner.py`)**:
   - **Baseline 1 (BM25 Only / Lucene相当)**: `BM25Engine` 単体による語彙照合。
   - **Baseline 2 (Dense Vector Only / Chroma・Qdrant相当)**: `DeterministicEmbedding` + コサイン類似度によるセマンティック検索。
   - **自作ハイブリッド (BM25 + HNSW Vector + Dual-CSR Graph)**: RRF (Reciprocal Rank Fusion, $k=60$) と知識グラフ 2-Hop スコア伝播を統合したハイブリッド探索。
   - 各モデルの指標を同一データセット上で一括評価し、比較 Markdown 表および JSON レポートを生成。
4. **公開レポートと自動化 (`docs/benchmarks/sota_evaluation.md`, `Makefile`)**:
   - ベンチマーク結果を Markdown 表および比較サマリーとして出力するジェネレータ。
   - `make benchmark_ir` を定義し、CI またはローカルで即座に実行可能にする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] BEIR / CTI-Bench 互換の評価データセットが外部ライブラリなしでロードおよび実行できること。
- [x] `BM25 単体` vs `Dense Vector 単体` vs `自作ハイブリッド (BM25+HNSW+Graph)` の精度（NDCG@10, Recall@K）および速度（QPS, Latency）が定量比較出力されること。
- [x] ハイブリッド探索が単一探索手法（BM25のみ、Vectorのみ）を NDCG@10 において有意に上回ることが実証されること。
- [x] `make benchmark_ir` コマンドでベンチマークが完走し、`docs/benchmarks/sota_evaluation.md` が生成されること。
- [x] 単体テスト `pytest tests/search/eval/test_sota_runner.py` が 100% PASS すること。
- [x] `make check_format` および `make static_analysis` がエラー0件で通過すること。
