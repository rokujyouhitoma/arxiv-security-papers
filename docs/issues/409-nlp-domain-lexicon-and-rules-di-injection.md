---
ID: 409
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 自然言語処理およびパイプライン層におけるドメイン固有語彙・文法規則・シソーラスの依存性注入 (DI) 化と責務分離 (ID: 409)

## 1. 概要 / Summary
現在、自然言語処理基盤 (`src/nlp/`) および関連パイプライン層において、以下のドメイン固有（Cybersecurity / 学術論文・特定言語）の辞書・文法規則・シソーラスがエンジン内部に直接ハードコードされている。

1. `_GRAMMAR_ENTRIES` ([src/nlp/morphology/viterbi_tokenizer.py](file:///workspace/arxiv-security-papers/src/nlp/morphology/viterbi_tokenizer.py)): 日本語形態素解析用文法エントリ
2. `_EN_STOPWORDS` / `_JA_STOPWORDS` ([src/nlp/lexicon/stop_words.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/stop_words.py)): 言語別ストップワード
3. `_ACADEMIC_NOISE` ([src/nlp/lexicon/stop_words.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/stop_words.py)): 学術論文特有のメタ語・定型ノイズ
4. `_SYNONYM_GROUPS` ([src/nlp/lexicon/security_thesaurus.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/security_thesaurus.py)): セキュリティ用語同義語クラスタ
5. `_EN_TO_JA_DICT` ([src/nlp/lexicon/security_thesaurus.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/security_thesaurus.py)): セキュリティ専門用語英和対訳辞書
6. `KEYWORD_TRANSLATIONS` / `PHRASE_REPLACEMENTS` ([src/nlp/summarization/structured_synthesizer.py](file:///workspace/arxiv-security-papers/src/nlp/summarization/structured_synthesizer.py)): 3点要約合成用キーワード・フレーズ置換辞書
7. `THREAT_MARKERS` / `PROPOSAL_MARKERS` / `IMPACT_MARKERS` 等 ([src/nlp/summarization/discourse_parser.py](file:///workspace/arxiv-security-papers/src/nlp/summarization/discourse_parser.py)): 談話構造スコアリングマーカー

これにより、「汎用アルゴリズム基盤」と「セキュリティドメイン知識」が密結合し、単体テスト時のモック差し替えや他分野ドメインへの適用、辞書の動的拡張が阻害されている。

### LISP 動的スコープ思想の導入
本課題では、Java 的な重厚な DI コンテナ（IoC Container）を新設するのではなく、リポジトリ既存の LISP 動的束縛基盤 **`src/pylisp/dynvar.py` (`DynamicVar`, `dynamic_bind`)** をバックボーンとして活用する。
オブジェクト指向的な「**Constructor Injection**（局所的・明示的注入）」と、LISP / Clojure 的な「**Dynamic Scope Injection**（中間層のバケツリレー不要なコンテキスト一括注入）」を融合した **ハイブリッド 3 段フォールバック DI アーキテクチャ** を確立する。

---

## 2. トレーサビリティ / Traceability
- 関連要求・設計:
  - `DSN-01`: システム高水準アーキテクチャ (NLPレイヤの疎結合・SPI適合規約)
  - `DSN-27`: 自然言語処理基盤 (Core SPI & Lexicon Separation)
  - `DSN-29`: LISP 言語基盤 (Phase 0: `pylisp.dynvar` 非同期セーフ動的スコープ)
  - Issue 389 (`pylisp.dynvar` 非同期セーフ動的スコープ基盤の実装)
  - Issue 405 (`src/nlp/` 共通パッケージ創設 & SPI定義)
  - Issue 406 (Pure-Python 形態素解析器 & セキュリティシソーラス)
  - Issue 407 (談話構造解析 & 3点構造化要約エンジン)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/nlp/core/context.py](file:///workspace/arxiv-security-papers/src/nlp/core/context.py) *(新規作成: NLP動的スコープ変数定義)*
- [ ] [src/nlp/lexicon/security_thesaurus.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/security_thesaurus.py)
- [ ] [src/nlp/lexicon/stop_words.py](file:///workspace/arxiv-security-papers/src/nlp/lexicon/stop_words.py)
- [ ] [src/nlp/morphology/viterbi_tokenizer.py](file:///workspace/arxiv-security-papers/src/nlp/morphology/viterbi_tokenizer.py)
- [ ] [src/nlp/summarization/structured_synthesizer.py](file:///workspace/arxiv-security-papers/src/nlp/summarization/structured_synthesizer.py)
- [ ] [src/nlp/summarization/discourse_parser.py](file:///workspace/arxiv-security-papers/src/nlp/summarization/discourse_parser.py)
- [ ] [src/nlp/segmentation/academic_segmenter.py](file:///workspace/arxiv-security-papers/src/nlp/segmentation/academic_segmenter.py)
- [ ] [src/pylisp/dynvar.py](file:///workspace/arxiv-security-papers/src/pylisp/dynvar.py) *(連携・利用)*
- [ ] [tests/nlp/](file:///workspace/arxiv-security-papers/tests/nlp/) (単体・回帰テスト全般)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/409-nlp-domain-lexicon-and-rules-di-injection`

### アーキテクチャ: 3 段フォールバック解決原則
各コンポーネントにおける依存関係（Thesaurus, Lexicon, Stopwords, Rules）は、以下の優先順位で自動解決される：
1. **Level 1 (Constructor)**: コンストラクタ引数で明示的に渡されたインスタンス・辞書（最優先・OOP単体テスト用）
2. **Level 2 (Dynamic Scope)**: 現在の動的コンテキスト (`CURRENT_*.value`)（`with dynamic_bind(...)` によるスコープ限定差し替え用）
3. **Level 3 (Default Fallback)**: 組み込みデフォルト定数・インスタンス（完全後方互換性担保）

### 実装フェーズ

1. **Phase 1: NLP 動的コンテキスト (`src/nlp/core/context.py`) の創設**
   - `src/pylisp/dynvar.py` の `DynamicVar` を用いて、NLP 全体で共有可能な動的環境変数を宣言：
     - `CURRENT_THESAURUS: DynamicVar[SecurityThesaurus]`
     - `CURRENT_STOPWORDS: DynamicVar[FrozenSet[str]]`
     - `CURRENT_GRAMMAR_ENTRIES: DynamicVar[Tuple[Tuple[str, int, str], ...]]`
     - `CURRENT_DISCOURSE_MARKERS: DynamicVar[DiscourseMarkerConfig]`
     - `CURRENT_SYNTHESIZER_RULES: DynamicVar[SynthesizerRuleConfig]`

2. **Phase 2: シソーラス・ストップワード層の DI 対応**
   - `SecurityThesaurus.__init__(translation_dict=None, synonym_groups=None)`:
     - 引数未指定時は `CURRENT_EN_TO_JA_DICT.value` / `CURRENT_SYNONYM_GROUPS.value` を経由してデフォルト定数にフォールバック。
   - `stop_words.py`: `STOPWORDS` コレクションの解決を `CURRENT_STOPWORDS.value` と連動可能にし、外部差し替えを容易化。

3. **Phase 3: 形態素解析器・トークナイザー層の DI 対応**
   - `PureMorphTokenizer.__init__(trie=None, grammar_entries=None, thesaurus=None)`:
     - `thesaurus` を明示的または `CURRENT_THESAURUS.value` から解決。
     - `_build_default_trie()` が `SecurityThesaurus` をハードコード生成していた結合を完全解消。

4. **Phase 4: 談話構造解析器・要約合成器層の DI 対応**
   - `DiscourseRhetoricParser.__init__(marker_config=None)`:
     - `THREAT_MARKERS`, `PROPOSAL_MARKERS`, `IMPACT_MARKERS` 等を `marker_config` または `CURRENT_DISCOURSE_MARKERS.value` から解決。
   - `StructuredSynthesizer.__init__(..., rules=None)`:
     - `KEYWORD_TRANSLATIONS`, `PHRASE_REPLACEMENTS`, テンプレートフォールバック文字列を `rules` または `CURRENT_SYNTHESIZER_RULES.value` から解決。

5. **Phase 5: 文境界解析器層の DI 対応**
   - `AcademicSentenceSegmenter.__init__(..., abbreviations=None, ref_patterns=None)`: 学術略語パターンの動的解決対応。

6. **Phase 6: 包括的単体テストと動的束縛 (DI) 実証**
   - **Constructor DI テスト**: 個別インスタンス生成時にカスタム辞書を渡して動作確認。
   - **LISP Dynamic Scope DI テスト**: `with dynamic_bind({CURRENT_THESAURUS: custom_thesaurus}):` 内でパイプライン一式を実行し、引数を一切引き回さずに全コンポーネントがカスタム辞書で動作することを実証。
   - 既存テスト全件の後方互換性確認（引数なし呼出で 100% PASS）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/nlp/core/context.py` が創設され、`pylisp.dynvar.DynamicVar` に基づく動的環境変数が定義されていること。
- [ ] 対象クラス（`SecurityThesaurus`, `PureMorphTokenizer`, `StructuredSynthesizer`, `DiscourseRhetoricParser`, `AcademicSentenceSegmenter`）が引数なしで既存通り正常動作すること（完全後方互換性）。
- [ ] コンストラクタ引数による局所的 DI、および `dynamic_bind` による動的スコープ DI の両方が動作することを検証する単体テストが存在すること。
- [ ] `make format`, `make static_analysis` (flake8, mypy, xenon Rank A) がエラー 0 件で通過すること。
- [ ] `make test` (pytest) が全件 PASS すること。
