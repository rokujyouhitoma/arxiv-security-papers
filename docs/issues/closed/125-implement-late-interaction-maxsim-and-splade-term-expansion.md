---
ID: 125
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Late-Interaction（MaxSim）演算機構およびセキュリティ専門語彙拡張（SPLADE風疎表現）リランカーの実装 (ID: 125)

## 1. 概要 / Summary
セキュリティ文献における専門用語や頭字語（例: PQC, PEP/PDP, ATT&CK T1059, ASLR, ROP）の表記揺らぎや同義語ギャップを埋めるため、ColBERT 型の Late-Interaction 演算（MaxSim: クエリ・ドキュメント間の各トークン埋め込み内積の最大値総和）と、疎表現語彙拡張（SPLADE 風アプローチ）を内製 Pure-Python エンジン（ゼロ外部依存）上に実装する。

従来の単一ベクトル集約（Dense ANN）で失われがちだった特定キーワードの微細なニュアンスをトークンレベルで保持し、BM25 語彙検索 / Dense ANN ベクトル探索の第 1 段階候補生成（Top-50）に対し、第 2 段階リランカーとして MaxSim と SPLADE 拡張スコアを線形結合・適用することで、サブミリ秒オーダーの高速性を保ちながら高精度な再順位付けを実現する。

---

## 2. トレーサビリティ / Traceability
- [DSN-04: 検索エンジン・プラットフォーム](../../docs/designs/DSN-04-search_engine_and_platform.md)
- [REQ-03: プロジェクトユースケース台帳 (UC-RES-01, UC-RES-02)](../requirements/REQ-03-use_case_ledger.md)
- [Issue 124: BM25語彙検索とDense ANN意味検索を統合するRRFハイブリッドスコアラー](closed/124-implement-bm25-dense-ann-reciprocal-rank-fusion-scorer.md)
- [Issue 117: 内製Pure-Python埋め込みエンジンの意味的セマンティック類似度向上](closed/117-enhance-pure-python-semantic-embeddings.md)
- [src/search/ranking/](../../src/search/ranking/)
- [src/search/vector_engine.py](../../src/search/vector_engine.py)
- [src/search/vector/hybrid.py](../../src/search/vector/hybrid.py)

---

## 3. 脅威モデリングとセキュリティ要件 (Threat Modeling & Mitigations)
- **T-125-01: クエリ／ドキュメント長大化による $O(|Q| \times |D|)$ 行列演算 DoS**
  - *脅威*: 悪意あるユーザーが極端に長いトークン列を含むクエリを送信した場合、二重ループによる内積計算回数が爆発し、Search ワーカーの CPU を枯渇させる。
  - *対策*: クエリトークン数上限を $|Q| \le 32$、ドキュメント評価トークン数上限を $|D| \le 128$ に切り詰め、候補ドキュメント数を最大 50 件に制限するガードレールを強制。
- **T-125-02: 専門用語同義語辞書の外部注入・汚染によるスコア操作**
  - *脅威*: 辞書ファイルやシノニムマップが動的に改ざんされ、特定論文のスコアを不正に吊り上げる、または重要論文を不可視化する。
  - *対策*: 辞書定義を不変タプル・フローズンセットとしてコードベース内にハードニングし、外部からの未検証な辞書ロードを排除。
- **T-125-03: 浮動小数点演算における NaN / Inf 伝播によるソート破壊**
  - *脅威*: ゼロノルムベクトルとの内積やオーバーフローによって NaN または Inf が混入し、Python の `sort()` 順序が未定義動作に陥る。
  - *対策*: 内積計算時に正規化チェック（$\epsilon = 10^{-9}$）を実施し、`math.isnan()` / `math.isinf()` を検証して安全なデフォルト値 $0.0$ にフォールバック。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/search/ranking/late_interaction.py` (ColBERT MaxSim 演算子および Late-Interaction スコアラーの実装)
- [x] `src/search/ranking/splade_expansion.py` (セキュリティ専門語彙・オントロジー辞書に基づく SPLADE 風疎表現拡張器)
- [x] `src/search/ranking/__init__.py` (新規リランカーモジュールの公開エクスポート)
- [x] `src/search/vector_engine.py` (第 2 段階リランカーパイプライン統合 `search_late_interaction()`)
- [x] `tests/search/test_late_interaction.py` (MaxSim 演算の正当性、性能、境界値テスト)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/125-implement-late-interaction-maxsim-and-splade-term-expansion`

1. **ステップ 1: MaxSim 演算エンジンの実装 (`src/search/ranking/late_interaction.py`)**:
   - 純粋 Python 標準ライブラリ (`math`) のみを用いたトークン埋め込みリスト間の内積計算関数 `dot_product(vec_a, vec_b) -> float` を実装。
   - `compute_maxsim(query_embeddings: List[List[float]], doc_embeddings: List[List[float]]) -> float` を定義。数式 $\sum_{i=1}^{|Q|} \max_{j=1}^{|D|} (E_{q_i} \cdot E_{d_j})$ に従い、各クエリトークンに対するドキュメントトークンの最大類似度の総和を算出。
   - `LateInteractionReranker` クラスを作成し、候補ドキュメントリストに対するバッチリランキングと正規化スコアリングを実装。
2. **ステップ 2: セキュリティ専門語彙拡張器の実装 (`src/search/ranking/splade_expansion.py`)**:
   - `SpladeTermExpander` クラスを作成し、セキュリティ頭字語（PQC $\rightarrow$ post-quantum cryptography, ROP $\rightarrow$ return-oriented programming, XSS $\rightarrow$ cross-site scripting）および MITRE ATT&CK / CWE の関連語彙マップを内蔵。
   - トークン頻度と IDF を考慮した対数飽和重み $\log(1 + w)$ による疎ベクトル重み付けを生成。
   - クエリおよびドキュメントの語彙疎表現を合成する `expand_query(tokens: List[str]) -> Dict[str, float]` を実装。
3. **ステップ 3: `VectorEngine` への統合 (`src/search/vector_engine.py`)**:
   - `search_late_interaction(query: str, top_k: int = 10, candidate_k: int = 50)` メソッドを追加。
   - 第 1 段階で既存の `search_rrf_hybrid()` から候補 `candidate_k` 件を取得。
   - 各候補論文のタイトル・概要トークン埋め込みに対し `LateInteractionReranker.rerank()` を適用。
   - SPLADE 疎表現スコアと MaxSim スコアを統合（$\text{final} = \alpha \cdot \text{MaxSim} + (1 - \alpha) \cdot \text{SPLADE}$）して Top-K を返却。
4. **ステップ 4: テストスイートの作成と品質検証**:
   - `tests/search/test_late_interaction.py` で MaxSim の対称性・非負性・トークン上限ガードを網羅。
   - `make format`, `make static_analysis` (Xenon Rank A, Mypy Strict), `pytest` 100% PASS を達成。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 外部依存（NumPy, PyTorch, SciPy 等）を一切使用せず標準ライブラリのみで MaxSim 演算が動作すること
- [x] 50 件の候補論文に対する MaxSim リランキング処理が 5 ミリ秒以内で完了すること
- [x] クエリートークン上限（32件）およびドキュメントトークン上限（128件）のクリッピングが正常に機能すること
- [x] 頭字語（例: "PQC", "ATT&CK"）を含む検索クエリにおいて、展開語彙によるドキュメント捕捉率が向上すること
- [x] 全品質ゲート（Xenon Rank A, Flake8 0 errors, Mypy Strict 0 errors, pytest 100% PASS）を満たすこと
