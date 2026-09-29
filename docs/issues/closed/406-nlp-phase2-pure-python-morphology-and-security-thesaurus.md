---
ID: 406
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 自然言語処理基盤 Phase 2: Pure-Python 形態素解析器・Trie木辞書・セキュリティ専門語シソーラスの実装 (ID: 406)

## 1. 概要 / Summary

設計書 [DSN-19](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md) 第8章・第9章に基づき、外部ライブラリ（MeCab, Janome, Sudachi 等）に一切依存しない、純粋 Python 実装の日本語・日英混在セキュリティ形態素解析エンジン（`PureMorphTokenizer`）およびセキュリティ専門用語シソーラス（`SecurityThesaurus`）を構築する。

現行システムでは、日本語の分かち書きが「文字種正規表現＋隣接2文字のBigram（`StandardTokenizer`）」にとどまり、「マルウェア分類手法」が単なる2文字断片に分断され、検索ノイズや誤マッチの温床となっていた。本 Issue では、高速プレフィックス Trie 木辞書（`PrefixTrie`）と最長一致・最小コストパス探索（Viterbi アルゴリズム）を実装し、CVE, CWE, MITRE ATT&CK などのセキュリティ複合語を正確に単語単位で分かち書き可能とする。さらに検索エンジン（`src/search/core/analysis/`）のトークナイザーと統合し、高精度なセマンティック検索・キーワード抽出の礎を築く。

---

## 2. トレーサビリティ & 脅威分析 / Traceability & Threat Analysis

### 2.1 トレーサビリティ
- **設計仕様書**:
  - [DSN-19: 自然言語処理（NLP）重要キーワード抽出・3点構造化要約・横断的動向シンセシス包括的アーキテクチャ設計書](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md) (第8章・第9章)
  - [DSN-14: Enterprise Multi-Field Hybrid & Multi-Stage RAG Search Engine Platform](../../docs/designs/DSN-14-search_engine.md)
- **関連 Issue**:
  - [Issue 405 (Closed): 自然言語処理基盤 Phase 1: src/nlp/ 共通パッケージ創設・SPI定義・学術文境界解析器の実装](closed/405-nlp-phase1-core-package-spi-and-academic-segmenter.md)
  - [Issue 407 (Open): 自然言語処理基盤 Phase 3: 談話構造解析・否定文＆モダリティ検知付き3点構造化要約エンジンの高度化](407-nlp-phase3-discourse-rhetoric-and-structured-summarizer.md)
- **アーキテクチャ規約**:
  - ゼロ外部依存（標準ライブラリのみ）・Pure Python
  - Xenon 循環的複雑度 CC <= 3 (Rank A) を全関数で厳格遵守
  - `mypy --strict` 適合（型注釈 100% 網羅）
  - 高速プレフィックス Trie 探索（単語長 $L$ に対して $O(L)$）

### 2.2 セキュリティ・脅威分析 (Threat Modeling & Mitigation)
- **脅威 1: 未知語連続による探索爆発 (Algorithmic Complexity DoS / CWE-400)**
  - *リスク*: 辞書に存在しない異常な長大文字列（数千文字の連続した未知文字）に対して Viterbi 格子グラフを作成すると、エッジ数が爆発し探索時間・メモリが増大する。
  - *対策*: 未知語の最大許容長（例: 32文字）による刈り込み（Pruning）および最長一致法によるフォールバックを組み合わせ、探索空間を $O(N)$（$N$ は文字列長）に制限する。
- **脅威 2: シソーラス・辞書の不正注入・汚染 (Data Injection)**
  - *リスク*: 外部から取り込まれたシソーラスエントリに制御文字や不正な正規表現、過大な同義語ループが含まれることによる無限再帰・スタックオーバーフロー。
  - *対策*: シソーラスエントリの不変性（Frozen/Tuple化）、循環参照検出（DAG検証）、および単語サニタイズ（制御文字除去）を強制。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [x] [src/nlp/morphology/__init__.py](../../src/nlp/morphology/__init__.py): 形態素解析サブパッケージ初期化
- [x] [src/nlp/morphology/trie.py](../../src/nlp/morphology/trie.py): 高速プレフィックス Trie 木辞書コンテナ (`PrefixTrie`, `TrieNode`)
- [x] [src/nlp/morphology/viterbi_tokenizer.py](../../src/nlp/morphology/viterbi_tokenizer.py): 最小コストパス / 最長一致 Pure-Python 形態素解析器 (`PureMorphTokenizer`)
- [x] [src/nlp/lexicon/__init__.py](../../src/nlp/lexicon/__init__.py): 語彙・辞書サブパッケージ初期化
- [x] [src/nlp/lexicon/security_thesaurus.py](../../src/nlp/lexicon/security_thesaurus.py): セキュリティ専門用語・シソーラス・類義語辞書 (`SecurityThesaurus`)
- [x] [src/nlp/lexicon/stop_words.py](../../src/nlp/lexicon/stop_words.py): 日英統合ストップワード & 学術ノイズ語集 (`StopWords`)
- [x] [tests/nlp/test_trie.py](../../tests/nlp/test_trie.py): Trie 木の挿入・プレフィックス検索・空木エッジケーステスト
- [x] [tests/nlp/test_morphology.py](../../tests/nlp/test_morphology.py): 日本語・セキュリティ複合語分かち書き精度・未知語耐性・ReDoS耐性テスト
- [x] [tests/nlp/test_thesaurus.py](../../tests/nlp/test_thesaurus.py): セキュリティ用語対訳・同義語展開・ストップワードフィルタテスト

### 修正対象ファイル
- [x] [src/nlp/__init__.py](../../src/nlp/__init__.py): `PureMorphTokenizer`, `PrefixTrie`, `SecurityThesaurus`, `StopWords` を公開ファサードに追加
- [x] [src/search/core/analysis/tokenizer.py](../../src/search/core/analysis/tokenizer.py): `StandardTokenizer` に形態素解析モードを追加し、`PureMorphTokenizer` との透過的連携をサポート
- [x] [docs/issues/README.md](README.md): Issue 台帳の進捗更新 (`Closed`)

---

## 4. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `feat/406-nlp-phase2-pure-python-morphology-and-security-thesaurus`

### ステップ 1: `src/nlp/morphology/trie.py` の実装
- `TrieNode`（スロット化 dataclass）と `PrefixTrie` を実装：
  - `insert(word: str, value: Any = None) -> None`: 単語とメタデータ（品詞、コスト等）を登録。
  - `common_prefix_search(text: str, start: int = 0) -> List[Tuple[str, Any]]`: 指定位置から始まる辞書内プレフィックス単語とその値を最長一致順または全候補で返却。
  - `search(word: str) -> Optional[Any]`: 完全一致判定。

### ステップ 2: `src/nlp/lexicon/security_thesaurus.py` & `stop_words.py` の整備
1. **セキュリティ専門語辞書**:
   - 暗号（`QKD`, `AES`, `ポスト量子暗号`, `格子暗号`, `Zero-Knowledge Proof`）
   - 攻撃手法（`RowHammer`, `サイドチャネル攻撃`, `フォールト注入`, `プロンプトインジェクション`, `ジェイルブレイク`）
   - 脆弱性・防御（`バッファオーバーフロー`, `権限昇格`, `ゼロトラスト`, `差分プライバシー`, `メモリ安全性`）
   - MITRE ATT&CK / STRIDE 用語
2. **基本日本語機能語辞書**:
   - 助詞（`は`, `が`, `の`, `に`, `を`, `で`, `と`, `から`, `より`, `へ`）
   - 助動詞・接続詞（`である`, `です`, `ます`, `また`, `しかし`, `および`）
3. **日英ストップワード**:
   - 学術ノイズ（`paper`, `study`, `propose`, `本論文`, `提案`, `研究`, `評価` 等）

### ステップ 3: `src/nlp/morphology/viterbi_tokenizer.py` の実装
- `MorphologicalAnalyzerSPI` および `TokenizerSPI` に準拠する `PureMorphTokenizer` を実装：
  - **最長一致＋動的計画法 (Viterbi / Forward-DP)**:
    - 辞書登録語は低コスト（10〜100）、未知語は文字種遷移（漢字・ひらがな・カタカナ・英数字）に基づくペナルティコストを付与。
    - 単語生起コスト $C(w)$ の累積和を最小化するパスを線形 $O(N \cdot L)$ で探索。
  - カタカナ長音・連続カタカナを単一の複合語トークンとして保護。
  - 出力: `List[Morpheme]` および `List[Token]`（正確な文字オフセット `Span` 付き）。

### ステップ 4: 検索エンジン `src/search/core/analysis/tokenizer.py` との統合
- `StandardTokenizer` に `use_morphology: bool = False` オプションを追加し、有効時は CJK 領域に対して `PureMorphTokenizer` を用いた意味のある形態素単位のインデックス化を可能にする。
- 既存の Bigram 抽出との完全な後方互換性を維持。

### ステップ 5: 品質検証 & テストスイート
- `tests/nlp/test_trie.py`: 単語挿入、共通プレフィックス探索、完全一致、空文字。
- `tests/nlp/test_morphology.py`:
  - セキュリティ複合語「サイドチャネル攻撃」「プロンプトインジェクション」「ゼロデイ脆弱性」が単一トークンとして正しく抽出されること。
  - 日英混在文「SpecShieldはSpectre脆弱性を防ぐ新しい手法である」の正確な分かち書き。
  - 長大未知語に対する探索時間・メモリの健全性（DoS耐性）。
- `tests/nlp/test_thesaurus.py`: シソーラスの対訳・同義語ルックアップ、ストップワード判定。
- `make check_format`, `make static_analysis` (CC <= 3, mypy --strict), `make test` 100% PASS。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/nlp/morphology/trie.py` にプレフィックス Trie 木が実装され、計算量 $O(L)$ で動作すること。
- [x] `src/nlp/morphology/viterbi_tokenizer.py` が `MorphologicalAnalyzerSPI` に適合し、外部ライブラリなしで日本語・英日混在テキストを形態素解析できること。
- [x] セキュリティ専門用語（「サイドチャネル攻撃」「プロンプトインジェクション」等）が正しく単一の形態素として認識されること。
- [x] `src/nlp/lexicon/` 配下に専門用語シソーラスおよび日英ストップワード辞書が型安全に整備されていること。
- [x] `src/search/core/analysis/tokenizer.py` と後方互換性を保ちつつシームレスに連携できること。
- [x] `tests/nlp/` 配下の全テスト、および既存パイプライン・検索テストが 100% PASS すること。
- [x] `xenon --max-absolute A` (CC <= 3) および `mypy --strict` の静的解析を 0 エラーでパスすること。

