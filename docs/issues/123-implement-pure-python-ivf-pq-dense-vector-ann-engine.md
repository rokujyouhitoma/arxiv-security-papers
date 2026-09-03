---
ID: 123
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] mmap・struct駆動 Pure-Python IVF-PQ（転置インデックス積量子化）高密度ベクトルANN探索エンジンの実装 (ID: 123)

## 1. 概要 / Summary
外部のベクトル検索ライブラリや重量級 C-lib（Faiss, Annoy 等）に一切依存せず、Python 標準ライブラリの `struct` モジュールによる固定長バイナリパッキングと `mmap` によるゼロコピーメモリマッピングを組み合わせた、Pure-Python による転置インデックス付き積量子化（Inverted File with Product Quantization: IVF-PQ）近似最近傍探索（ANN）エンジンを実装する。
数万件規模の論文埋め込みベクトル（128〜384次元）を省メモリに保持しつつ、サブミリ秒オーダーの近傍探索を実現する。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [src/search/vector/](../../src/search/vector/)
- [src/database/index/embedding.py](../../src/database/index/embedding.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/search/vector/ivf_pq.py`
- [ ] `src/search/vector/quantization.py`
- [ ] `src/search/vector_engine.py`
- [ ] `tests/search/test_ivf_pq.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/123-implement-pure-python-ivf-pq-dense-vector-ann-engine`
1. K-Means クラスタリングによる IVF 重心セルの算出と転置インデックス構築。
2. サブスペース分割による Product Quantization（PQ コードブック生成と 1 バイトコード化）。
3. 非対称距離計算（ADC）ルックアップテーブルの高速参照。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 外部依存ゼロ（標準ライブラリのみ）で IVF-PQ ANN 探索が動作すること
- [ ] 10,000 件規模のベクトルに対して 1ms 未満で Top-K 探索が完了すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
