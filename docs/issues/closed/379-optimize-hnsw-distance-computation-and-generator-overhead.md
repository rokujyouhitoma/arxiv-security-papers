---
ID: 379
種別: Optimization
優先度: High
ステータス: Closed
---

# [OPT/ENH] HNSW ベクトル内積計算におけるジェネレータ多重呼出オーバーヘッドの解消と高速化 (ID: 379)

## 1. 概要 / Summary

PyNYTProf による `src/database` の高精度プロファイリングにおいて、`HNSWIndex._distance` 内の内積計算（`sum(x * y for x, y in zip(v1, v2))`）が **4,502,690 回** 呼び出され、**18,089.93 ms（全体の 40% 超）** を単一のジェネレータ評価行で消費していることが判明した。
本 Issue では、ジェネレータ内包表記および `zip()` によるフレーム割り当てを排除し、Python 標準の組み込み関数 `map` と `operator.mul` による `sum(map(operator.mul, v1, v2))` への移行、および `__init__` での距離計算ディスパッチ事前バインド（分岐ゼロ化）によって、Pure Python（外部依存ゼロ）のまま内積計算・近似近傍探索（ANN）の処理速度を大幅に向上させた。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Vector Database & HNSW Graph Index)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/index/index.py` (HNSWIndex 実装)
  - `src/database/index/embedding.py` (DeterministicEmbedding 実装)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`src/database/index/index.py`](file:///workspace/arxiv-security-papers/src/database/index/index.py) (`HNSWIndex._distance`, `_similarity_from_distance`, `__init__` でのディスパッチ事前バインド)
- [x] [`src/database/index/embedding.py`](file:///workspace/arxiv-security-papers/src/database/index/embedding.py) (`_vector_norm`, `_vector_dot`, `DeterministicEmbedding.normalize`)
- [x] [`scripts/benchmark_hnsw_micro.py`](file:///workspace/arxiv-security-papers/scripts/benchmark_hnsw_micro.py) (定量ベンチマーク測定)
- [x] [`tests/database/test_deterministic_embedding.py`](file:///workspace/arxiv-security-papers/tests/database/test_deterministic_embedding.py)
- [x] [`tests/database/compat/test_db_performance_and_memory.py`](file:///workspace/arxiv-security-papers/tests/database/compat/test_db_performance_and_memory.py)

---

## 4. 実装結果と性能検証 / Implementation & Performance Results

Target Branch: `opt/379-optimize-hnsw-distance-computation`

### 4.1. 修正前 (Baseline) vs 修正後 (Optimized) 比較

`scripts/benchmark_hnsw_micro.py` によるベンチマーク実測値：

| 項目 | 修正前 (Baseline) | 修正後 (Optimized) | 改善率 / 高速化倍率 |
|---|---|---|---|
| **純粋内積計算 (100,000 ops, dim=128)** | **0.3868 秒** | **0.2400 秒** | **1.61倍 高速化 (37.9% 短縮)** |
| **HNSW インデックス構築 (500 vectors)** | **2.8300 秒** | **1.8624 秒** | **1.52倍 高速化 (34.2% 短縮)** |
| **HNSW ANN 検索時間 (500 queries)** | **1.1178 秒** | **0.7356 秒** | **1.52倍 高速化 (34.2% 短縮)** |
| **ANN 検索スループット (QPS)** | **447.31 qps** | **679.68 qps** | **+51.9% 向上** |
| **平均検索レイテンシ** | **2.2356 ms** | **1.4713 ms** | **0.764 ms 短縮 (34.2% 低減)** |

### 4.2. コア最適化設計
1. **ジェネレータ式と zip の排除**:
   - `operator.mul` による `sum(map(operator.mul, v1, v2))` を採用。Pure Python のまま中間ジェネレータオブジェクトの生成を排除。
2. **メソッドディスパッチの事前バインド**:
   - `HNSWIndex.__init__` 内で、指定された `distance_metric` に応じて `self._distance_fn` / `self._similarity_fn` に専用関数ポインタを事前バインド。450万回の呼び出し毎に発生する `if self.metric in ...` の文字列探索と分岐を完全除去。
3. **ユークリッド距離の最適化**:
   - ユークリッド距離計算も同様に差分二乗の `sum(map(operator.mul, diff, diff))` へ移行。
4. **`embedding.py` のヘルパー最適化**:
   - `_vector_norm` および `_vector_dot` も同様に `sum(map(operator.mul, ...))` を適用。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/database/index/index.py` の `_distance` におけるジェネレータオブジェクト割り当てが完全にゼロ化されていること。
- [x] 修正後ベンチマークにおいて、HNSW ANN 検索スループット（QPS）およびインデックス構築速度が向上していること（向上率を定量的に記録: +51.9% QPS向上）。
- [x] 既存のすべてのベクトル・HNSW 関連テスト（`tests/database/test_deterministic_embedding.py`, `tests/database/compat/test_db_performance_and_memory.py`、および database 全 446 件のテスト）が 100% PASS すること。
- [x] `make check_format`、`make static_analysis`、`make py_compile` の品質ゲートをすべて通過すること。
- [x] コード内に `# noqa: E402` などの警告抑制コメントを含めないこと。


