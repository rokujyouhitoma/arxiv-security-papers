---
ID: 379
種別: Optimization
優先度: High
ステータス: Open (New)
---

# [OPT/ENH] HNSW ベクトル内積計算におけるジェネレータ多重呼出オーバーヘッドの解消と高速化 (ID: 379)

## 1. 概要 / Summary

PyNYTProf による `src/database` の高精度プロファイリングにおいて、`HNSWIndex._distance` 内の内積計算（`sum(x * y for x, y in zip(v1, v2))`）が **4,502,690 回** 呼び出され、**18,089.93 ms（全体の 40% 超）** を単一のジェネレータ評価行で消費していることが判明した。
本 Issue では、ジェネレータ内包表記および `zip()` によるフレーム割り当てを排除し、インデックス直接アクセスまたはアンロールされた算術ループへの移行によって、内積計算・近似近傍探索（ANN）の処理速度を大幅に向上させる。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - `docs/designs/DSN-05-database_engine_architecture.md` (Vector Database & HNSW Graph Index)
  - `outputs/profiling/html/index.html` (PyNYTProf プロファイル計測レポート)
  - `src/database/index/index.py` (HNSWIndex 実装)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [`src/database/index/index.py`](file:///workspace/arxiv-security-papers/src/database/index/index.py) (`HNSWIndex._distance`, `_evaluate_neighbor`, `_insert_lower_layers`)
- [ ] [`src/database/index/embedding.py`](file:///workspace/arxiv-security-papers/src/database/index/embedding.py) (`_vector_norm`, `DeterministicEmbedding.normalize`)
- [ ] [`tests/database/test_deterministic_embedding.py`](file:///workspace/arxiv-security-papers/tests/database/test_deterministic_embedding.py)
- [ ] [`tests/database/compat/test_db_performance_and_memory.py`](file:///workspace/arxiv-security-papers/tests/database/compat/test_db_performance_and_memory.py)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `opt/379-optimize-hnsw-distance-computation`

1. `HNSWIndex._distance` における `sum(x * y for x, y in zip(v1, v2))` を、ジェネレータを介さない直接ループ（`dot = 0.0; for i in range(len(v1)): dot += v1[i] * v2[i]`）等にリファクタリング。
2. コサイン類似度計算時の `max(0.0, 1.0 - dot)` の事前正規化前提チェックの最適化。
3. `DeterministicEmbedding.normalize` におけるノルム計算のジェネレータ排除。
4. 既存の HNSW 単体テストおよびスループットベンチマーク（`test_hnsw_ann_latency_percentiles`）の実行による性能改善確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `src/database/index/index.py` の `_distance` におけるジェネレータオブジェクト割り当てが完全にゼロ化されていること。
- [ ] PyNYTProf 再計測において `_distance.<locals>.<genexpr>` のホットスポットが解消されていること。
- [ ] 既存のすべてのベクトル・HNSW 関連テストが 100% PASS すること。
- [ ] `make py_compile`, `make format`, `make static_analysis` の品質ゲートを通過すること。
