---
ID: 407
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 自然言語処理基盤 Phase 3: 談話構造解析・否定文＆モダリティ検知付き3点構造化要約エンジンの高度化 (ID: 407)

## 1. 概要 / Summary

設計書 [DSN-19](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md) 第8章・第9章に基づき、論文アブストラクトから学術的レトリック構造を読み解く談話構造解析器（`DiscourseRhetoricParser`）および、否定文・モダリティ（確信度・実証強度）を考慮した高精度な 3 点構造化要約エンジン（`StructuredSynthesizer`）を構築した。あわせて、既存のキーワード抽出コンポーネント（TextRank, C-Value）を `src/nlp/extraction/` に正式昇格・整理し、SPI インターフェース（`KeyphraseExtractionSPI`, `DiscourseSummarizerSPI`）に準拠させた。

現行の `structured_summarizer.py` は、キーワードの単純出現回数で文をスコアリングしているため、「We do not propose a new cipher...」のような否定文や先行研究の解説文（"prior work demonstrates..."）を「提案手法」と誤認する課題があった。本 Issue では、否定詞（`not`, `never`, `cannot`, `fail`, `without`）による提案スコアの減衰・反転、先行研究文の識別、および実証強度（`demonstrate`, `empirically prove`, `achieve`, `outperform`）を考慮したアスペクト分類モデルを導入し、【背景・課題】【提案手法】【実証結果・影響】の3点要約の質を飛躍的に向上させた。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-19: 自然言語処理（NLP）重要キーワード抽出・3点構造化要約・横断的動向シンセシス包括的アーキテクチャ設計書](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md)
- **関連 Issue**:
  - [Issue 405 (Closed): 自然言語処理基盤 Phase 1: src/nlp/ 共通パッケージ創設・SPI定義・学術文境界解析器の実装](405-nlp-phase1-core-package-spi-and-academic-segmenter.md)
  - [Issue 406 (Closed): 自然言語処理基盤 Phase 2: Pure-Python 形態素解析器・Trie木辞書・セキュリティ専門語シソーラスの実装](406-nlp-phase2-pure-python-morphology-and-security-thesaurus.md)
  - [Issue 408 (Open): 自然言語処理基盤 Phase 4: 動的トピッククラスタリングと5階層エグゼクティブサマリー自動連携](../408-nlp-phase4-dynamic-topic-clustering-and-executive-sync.md)
- **アーキテクチャ規約**:
  - ゼロ外部依存・アスペクト分類モデル・Xenon CC <= 3 (Rank A)・Mypy Strict 適合
  - 100% 完全日本語出力契約

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [src/nlp/extraction/__init__.py](../../src/nlp/extraction/__init__.py) (新規: 重要語抽出公開ファサード)
- [x] [src/nlp/extraction/textrank.py](../../src/nlp/extraction/textrank.py) (新規: KeyphraseExtractionSPI準拠 TextRank)
- [x] [src/nlp/extraction/cvalue.py](../../src/nlp/extraction/cvalue.py) (新規: 専門複合名詞句抽出 C-Value)
- [x] [src/nlp/summarization/__init__.py](../../src/nlp/summarization/__init__.py) (新規: 談話要約公開ファサード)
- [x] [src/nlp/summarization/discourse_parser.py](../../src/nlp/summarization/discourse_parser.py) (新規: 否定文・先行研究文・モダリティ評価付き談話構造解析器)
- [x] [src/nlp/summarization/structured_synthesizer.py](../../src/nlp/summarization/structured_synthesizer.py) (新規: DiscourseSummarizerSPI準拠 3点構造化要約合成器)
- [x] [src/nlp/__init__.py](../../src/nlp/__init__.py) (新規コンポーネントのエクスポート追加)
- [x] [src/pipeline/transformer/structured_summarizer.py](../../src/pipeline/transformer/structured_summarizer.py) (`src/nlp/summarization/` への処理委譲ファサード化)
- [x] [src/pipeline/transformer/keyword_extractor.py](../../src/pipeline/transformer/keyword_extractor.py) (`src/nlp/extraction/` への処理委譲ファサード化)
- [x] [tests/nlp/test_extraction.py](../../tests/nlp/test_extraction.py) (新規: TextRank & C-Value 単体テスト)
- [x] [tests/nlp/test_discourse_parser.py](../../tests/nlp/test_discourse_parser.py) (新規: 否定文・先行研究文・実証文の識別テスト)
- [x] [tests/nlp/test_structured_synthesizer.py](../../tests/nlp/test_structured_synthesizer.py) (新規: 3点要約合成・日本語品質テスト)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の進捗更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/407-nlp-phase3-discourse-rhetoric-and-structured-summarizer`

1. **抽出基盤の移管と SPI 適合 (`src/nlp/extraction/`)**:
   - `textrank.py`: `KeyphraseExtractionSPI` に適合した `TextRankKeywordExtractor` を実装。`src/nlp/lexicon/stop_words.py` の `STOPWORDS` をデフォルト使用。
   - `cvalue.py`: 学術論文向け大文字キャメルケース・ハイフン区切り複合語抽出 `CValueExtractor` を実装。
   - 既存の `src/pipeline/transformer/keyword_extractor.py` から後方互換性を保ちつつ委譲。

2. **談話構造解析器 (`src/nlp/summarization/discourse_parser.py`)**:
   - `SentenceAspect` (THREAT, PROPOSAL, IMPACT) 列挙体および `AspectScore` データ構造の定義。
   - **否定文・反論の検知 (`NegationDetector`)**:
     - `not`, `never`, `cannot`, `can't`, `fail to`, `despite`, `without`, `neither` 等の否定詞のスコープ内の提案語スコアをゼロ化・反転。
   - **先行研究文の識別 (`PriorWorkDetector`)**:
     - `prior work`, `existing studies`, `traditionally`, `conventionally`, `previous literature` 等を含む文の提案スコアを抑制。
   - **モダリティ・実証強度評価 (`ModalityEvaluator`)**:
     - `demonstrate`, `empirically prove`, `achieve`, `outperform`, `reduce ... by`, `99%` 等の実証表現に対して高ウェイトを付与。
   - **マルチアスペクトスコアリング (`DiscourseRhetoricParser`)**:
     - 文位置（導入部・中間部・結び）と修辞マーカー・否定・先行研究補正を統合し、各文のアスペクトスコアを算出。

3. **3点構造化要約合成器 (`src/nlp/summarization/structured_synthesizer.py`)**:
   - `DiscourseSummarizerSPI` 準拠。
   - 談話解析結果から【背景・課題】【提案手法】【実証結果・影響】の代表文を選択。
   - `SecurityThesaurus`（Phase 2）の辞書引きを行い、英語専門用語を的確な日本語に置換・補正。
   - 単文エグゼクティブサマリー（`executive_summary`）を自動生成。
   - `src/pipeline/transformer/structured_summarizer.py` から本クラスへ委譲。

4. **テスト & 品質検証**:
   - `tests/nlp/` に網羅的な単体テストを追加。
   - Xenon CC <= 3 (Rank A)、`mypy --strict` 適合、`make check_format` 適合。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] 否定文（「〜を提案しない」「既存手法の限界」）が提案手法として誤抽出されないこと。
- [x] 先行研究の紹介文と論文自身の提案手法が明確に峻別されること。
- [x] 全ての出力サマリーが【背景】【提案】【実証】の3点構造化日本語フォーマットを満たすこと。
- [x] `src/nlp/extraction/` および `src/nlp/summarization/` が SPI プロトコル（`KeyphraseExtractionSPI`, `DiscourseSummarizerSPI`）に適合すること。
- [x] `src/pipeline/transformer/` の既存テストが後方互換性を保ち 100% PASS すること。
- [x] `make static_analysis` (mypy --strict, xenon CC <= 3) および全テストが 100% PASS すること。


