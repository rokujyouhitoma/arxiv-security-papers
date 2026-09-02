---
ID: 117
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 内製Pure-Python埋め込みエンジンの意味的セマンティック類似度向上（サブワード・N-gram重み付け＆超軽量埋め込み） (ID: 117)

## 1. 概要 / Summary
外部の巨大フレームワーク（PyTorch / Transformers / ONNX C-libs）に依存することなく、Pure Python のみで自然言語クエリの意味的類似度（Semantic Similarity）を向上させるため、サブワード分割、重要セキュリティ用語のIDF重み付け投影、およびコサイン類似度キャッシュを強化し、BM25/RRFハイブリッド検索の適合率を向上させる。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/database/embedding.py](../../src/database/embedding.py)
- [ ] [src/search/vector/hybrid.py](../../src/search/vector/hybrid.py)
- [ ] [src/search/vector_engine.py](../../src/search/vector_engine.py)
- [ ] [tests/database/storage/test_vector_storage.py](../../tests/database/storage/test_vector_storage.py)
- [ ] [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/117-enhance-pure-python-semantic-embeddings`

1. **Subword & Character N-Gram Hashing**: 複合語や新興脅威用語（例: `slopsquatting`, `prompt-injection`）に対応したサブワードトークナイズの導入。
2. **Contextual Dimensionality Projection**: セキュリティドメイン特化のシード語彙に基づく重み付き密ベクトル投影（384次元への拡張と正規化）。
3. **Information Retrieval (IR) Evaluation**: `src/search/eval/` の評価データセットを用いた NDCG@10 / MRR@10 のベンチマーク向上検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Pure Python 実装のまま自然言語クエリの NDCG@10 が向上すること
- [ ] 1クエリあたりのベクトル生成レイテンシが 5ms 未満を維持すること
- [ ] 全品質ゲート（Xenon Rank A, Flake8, pytest）を 100% パスすること
