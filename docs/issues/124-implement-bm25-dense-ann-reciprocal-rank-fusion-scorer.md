---
ID: 124
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] BM25語彙検索とDense ANN意味検索を統合するRRF（相互順位融合）ハイブリッドスコアラーの実装 (ID: 124)

## 1. 概要 / Summary
非有界な BM25 スコア体系と有界なコサイン類似度スコアの線形結合に伴うスケール不整合・極端値バイアスを排除するため、相互順位融合（Reciprocal Rank Fusion: RRF, 式 $RRF(d) = \sum_{m} \frac{1}{k + r_m(d)}$）を導入する。
標準算術演算のみで語彙・意味検索の順位を滑らかに統合し、正規化ハイパーパラメータ調整不要で適合率・順位品質を向上させる。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [src/search/vector/hybrid.py](../../src/search/vector/hybrid.py)
- [src/search/vector_engine.py](../../src/search/vector_engine.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `src/search/vector/hybrid.py`
- [ ] `src/search/vector_engine.py`
- [ ] `tests/search/test_rrf_hybrid.py`

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/124-implement-bm25-dense-ann-reciprocal-rank-fusion-scorer`
1. BM25 ランキングおよび Dense ANN ランキングからの独立順位 $r_m(d)$ 抽出。
2. 平滑化定数 $k=60$ を用いた調和スコア集計。
3. 同点時のタイブレークと Top-K 返却。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 語彙一致と意味類似度の順位が RRF により安定的に融合されること
- [ ] 単一手法よりも NDCG@10 が向上すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, Mypy Strict, pytest）を 100% パスすること
