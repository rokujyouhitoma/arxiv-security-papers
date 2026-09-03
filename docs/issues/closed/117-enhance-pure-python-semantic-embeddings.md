---
ID: 117
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 内製Pure-Python埋め込みエンジンの意味的セマンティック類似度向上（サブワード・N-gram重み付け＆超軽量埋め込み） (ID: 117)

## 1. 概要 / Summary
外部の巨大フレームワーク（PyTorch / Transformers / ONNX C-libs）に一切依存することなく、Pure Python のみで自然言語クエリおよび論文アブストラクトの意味的類似度（Semantic Similarity）を劇的に向上させる。
マルチスケール・サブワード分割 (Character 2-gram〜5-gram)、セキュリティドメイン特化のシード語彙・概念オントロジー投影、および IDF 重み付け投影を導入し、BM25/RRFハイブリッド検索 (ANN) の適合率 (Precision / Recall / NDCG@10) を向上させる。

### 目的 / Objectives
1. **マルチスケール・サブワード＆N-gram特徴ハッシュの拡張**:
   - 複合語、ハイフン区切り用語、新興セキュリティ概念（例: `prompt-injection`, `zero-trust`, `side-channel`, `slopsquatting`）を 2-gram〜5-gram のサブワード単位で高密度に特徴抽出。
2. **セキュリティドメイン特化セマンティック投影 (Semantic Seed Projection)**:
   - 暗号学、脆弱性解析、LLMセキュリティ、IoT/組み込み、ネットワーク防御、プライバシー保護などの主要セキュリティカテゴリを定義し、関連語が同一クラスタへ近づくようベクトル空間をアラインメント。
3. **IDF重み付け＆ストップワード抑制**:
   - 一般頻出語の寄与を低減し、情報利得の高い専門用語・識別子に高い重みを配分。
4. **ゼロオーバーヘッド＆完全下位互換性**:
   - `DeterministicEmbedding(dim=128)` のインターフェース互換性を 100% 維持し、1クエリあたり 1ms 未満の超高速処理を Pure Python で実現。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [DSN-05: データベースエンジンアーキテクチャ](../../docs/designs/DSN-05-database_engine_architecture.md)
- [src/database/index/embedding.py](../../src/database/index/embedding.py): 内製 DeterministicEmbedding 実装
- [src/database/embedding.py](../../src/database/embedding.py): 後方互換 shim
- [src/search/vector/](../../src/search/vector/): ベクトル検索・HNSW・RRF ハイブリッド層
- [tests/database/storage/test_vector_storage.py](../../tests/database/storage/test_vector_storage.py): ベクトル保存・コサイン類似度単体テスト
- [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py): ハイブリッド検索結合テスト
- [tests/database/test_deterministic_embedding.py](../../tests/database/test_deterministic_embedding.py): セマンティック類似度ベンチマークテスト

---

## 3. 脅威分析・運用制約 / Threat Analysis & Operational Constraints
1. **DoS / CPU 資源枯渇 (CWE-400 / Algorithmic Complexity Attack)**:
   - *脅威*: 異常に巨大なテキストや反復文字列が入力された場合に N-gram 生成ループで CPU が占有される。
   - *緩和策*: 入力テキストの最大長（例: 8,192文字）および最大トークン数を安全にクランプし、計算量を $O(N)$ にバウンド。
2. **ハッシュ衝突・ベクトル縮退**:
   - *脅威*: 特徴ハッシュの衝突により無関係な用語同士のコサイン類似度が異常上昇する。
   - *緩和策*: SHA-256 ビットスライスと符号付きプロジェクション（Signed Hash Projection）を採用し、平均ノルムの偏りを均一化。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/database/index/embedding.py](../../src/database/index/embedding.py)
- [x] [tests/database/storage/test_vector_storage.py](../../tests/database/storage/test_vector_storage.py)
- [x] [tests/database/test_deterministic_embedding.py](../../tests/database/test_deterministic_embedding.py)
- [x] [tests/search/test_vector_engine.py](../../tests/search/test_vector_engine.py)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/117-enhance-pure-python-semantic-embeddings`

1. **`src/database/index/embedding.py` の機能拡張**:
   - セキュリティドメインのシードオントロジーテーブル (`SECURITY_CONCEPT_SEEDS`) の定義。
   - マルチスケールサブワード抽出 (`_extract_subword_ngrams` / 2-gram〜4-gram)。
   - 符号付き特徴ハッシュ投影 (`_project_features_to_vector`)。
   - ドメインシード類似度バイアスの加算と L2 単位ベクトル正規化。
2. **類似度評価とテストの追加**:
   - `tests/database/test_deterministic_embedding.py` の新設:
     - 意味的に類似した用語（例: `zero-trust architecture` vs `zero trust network`, `prompt injection attack` vs `jailbreak llm`）が、無関係な単語（例: `cooking pasta recipe`）よりも有意に高いコサイン類似度 (> 0.6) を持つことを検証。
     - レイテンシ（< 5ms / query）と決定論的一貫性の検証。
3. **品質ゲート検証**:
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 関連するセキュリティ概念ペアのコサイン類似度が非関連ペアに対して統計的に有意に高い（コサイン類似度差分 $\ge 0.35$）こと
- [x] 1クエリ（500文字）あたりの埋め込み生成処理時間が 5ms 未満であること
- [x] `DeterministicEmbedding` の完全決定論性（同一入力に対して常に完全一致する Float32 ベクトル出力）が保証されること
- [x] 全ユニットテスト・統合テストおよび品質ゲート（`make format`, `make static_analysis` / Xenon Rank A, Mypy Strict）が 100% PASS すること


