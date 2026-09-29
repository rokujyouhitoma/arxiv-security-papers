---
ID: 405
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] 自然言語処理基盤 Phase 1: src/nlp/ 共通パッケージ創設・SPI定義・学術文境界解析器の実装 (ID: 405)

## 1. 概要 / Summary

設計書 [DSN-19](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md) 第8章・第9章に基づき、これまで `src/pipeline/transformer/` や `src/search/core/analysis/`、`src/database/index/` に散在していた自然言語処理（NLP）ロジックを統合・昇格するための共通基盤パッケージ `src/nlp/` を創設する。

本 Issue（Phase 1）では、以下を完遂する：
1. ドメイン非依存な SPI プロトコル群（`TokenizerSPI`, `SentenceSegmenterSPI`, `MorphologicalAnalyzerSPI`, `KeyphraseExtractionSPI`, `DiscourseSummarizerSPI`, `TopicClustererSPI`）の策定
2. 不変かつ型安全な共通データ構造（`Token`, `Span`, `Sentence`, `Morpheme`, `TopicCluster`）の実装
3. 学術論文の略語（`e.g.`, `i.e.`, `et al.`, `cf.`, `etc.` 等）、図表・文献参照（`Fig. 1`, `Table 2`, `Ref. [3]`）、バージョン・数値（`v1.2`, `CVE-2026-1234`）、引用符・括弧保護に対応した学術文境界解析器（`AcademicSentenceSegmenter`）の実装
4. 既存 `src/pipeline/transformer/structured_summarizer.py` とのシームレスな後方互換接続と 100% 互換性保証

---

## 2. トレーサビリティ & 脅威分析 / Traceability & Threat Analysis

### 2.1 トレーサビリティ
- **設計仕様書**:
  - [DSN-19: 自然言語処理（NLP）重要キーワード抽出・3点構造化要約・横断的動向シンセシス包括的アーキテクチャ設計書](../../docs/designs/DSN-19-nlp_keyphrase_extraction_and_structured_synthesis.md) (第8章・第9章)
  - [DSN-01: ハイレベルシステム設計書](../../docs/designs/DSN-01-high_level_design.md)
- **関連 Issue**:
  - [Issue 109 (Closed): 自然言語処理キーワード抽出と構造化要約](../../docs/issues/closed/109-enhance-executive-summaries-with-nlp-keyphrase-extraction-and-structured-synthesis.md)
  - [Issue 406 (Open): 自然言語処理基盤 Phase 2: Pure-Python 形態素解析器・Trie木辞書・セキュリティ専門語シソーラスの実装](406-nlp-phase2-pure-python-morphology-and-security-thesaurus.md)
  - [Issue 404 (Open): 最新OKF収集データの5階層エグゼクティブサマリー自動集約と動的Mermaidトレンド同期](404-okf-5-tier-executive-summary-sync-and-trend-analysis.md)
- **品質規約**:
  - ゼロ外部依存（標準ライブラリ `re`, `typing`, `dataclasses`, `collections`, `abc` のみ）
  - Xenon 循環的複雑度 CC <= 3 (Rank A) を全関数・全メソッドで厳守
  - `mypy --strict` 適合（型注釈 100% 網羅）

### 2.2 セキュリティ・脅威分析 (Threat Modeling & Mitigation)
- **脅威 1: 正規表現サービス運用妨害 (ReDoS: CWE-1333)**
  - *リスク*: 学術論文の極端に長い連続記号列やネストした引用符・括弧に対する正規表現マッチングにおいて、カタストロフィック・バックトラッキングが発生し CPU 枯渇に陥る。
  - *対策*: バックトラッキングを誘発する貪欲・ネスト量指定子（例: `(.*)+`）を完全排除し、線形時間 $O(N)$ で完結する文字走査または事前トークンエスケープ置換方式を採用。
- **脅威 2: 異常テキスト注入・メモリ枯渇 (Resource Exhaustion)**
  - *リスク*: 数十MBに及ぶ巨大な非構造化テキストやバイナリ混入テキストの入力による OOM。
  - *対策*: 入力長上限（デフォルト 1MB）のバリデーションを配置し、超過時は安全に切り詰めるか明確な例外を送出。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成ファイル
- [x] [src/nlp/__init__.py](../../src/nlp/__init__.py): パッケージルートおよび主要クラスのファサード公開
- [x] [src/nlp/core/__init__.py](../../src/nlp/core/__init__.py): コアサブパッケージ初期化
- [x] [src/nlp/core/protocols.py](../../src/nlp/core/protocols.py): ドメイン非依存 SPI プロトコル定義 (`TokenizerSPI`, `SentenceSegmenterSPI`, etc.)
- [x] [src/nlp/core/tokens.py](../../src/nlp/core/tokens.py): 共通データ構造 (`Token`, `Span`, `Sentence`, `Morpheme`, `TopicCluster`)
- [x] [src/nlp/segmentation/__init__.py](../../src/nlp/segmentation/__init__.py): 文分割サブパッケージ初期化
- [x] [src/nlp/segmentation/academic_segmenter.py](../../src/nlp/segmentation/academic_segmenter.py): 学術論文向け文境界解析器 (`AcademicSentenceSegmenter`)
- [x] [tests/nlp/__init__.py](../../tests/nlp/__init__.py): テストパッケージ初期化
- [x] [tests/nlp/test_core_protocols.py](../../tests/nlp/test_core_protocols.py): プロトコル契約およびデータ構造の不変性・シリアライズテスト
- [x] [tests/nlp/test_academic_segmenter.py](../../tests/nlp/test_academic_segmenter.py): 略語保護・数式・引用・ReDoS耐性・エッジケーステスト

### 修正対象ファイル
- [x] [src/pipeline/transformer/structured_summarizer.py](../../src/pipeline/transformer/structured_summarizer.py): 内部文分割関数 `_split_into_sentences` を `AcademicSentenceSegmenter` に委譲し、後方互換性を完全維持
- [x] [docs/issues/README.md](README.md): Issue 台帳のステータス更新 (`Closed`)

---

## 4. 詳細実装方針 / Detailed Implementation Plan

Target Branch: `feat/405-nlp-phase1-core-package-spi-and-academic-segmenter`

### ステップ 1: `src/nlp/core/tokens.py` の定義
- `@dataclass(frozen=True)` を用いてイミュータブルかつ軽量スロット化（`slots=True`）されたデータ構造を定義：
  - `Span(start: int, end: int)`
  - `Token(text: str, span: Span, tag: Optional[str] = None, lemma: Optional[str] = None)`
  - `Sentence(text: str, span: Span, tokens: Tuple[Token, ...] = ())`
  - `Morpheme(surface: str, pos: str, subpos: str, base_form: str, cost: int = 0)`
  - `TopicCluster(cluster_id: str, label: str, keywords: Tuple[str, ...], score: float, document_ids: Tuple[str, ...] = ())`

### ステップ 2: `src/nlp/core/protocols.py` の SPI 定義
- `typing.Protocol` および `@runtime_checkable` を用いて、言語・ドメイン非依存の SPI を策定：
  - `TokenizerSPI`: `tokenize(text: str) -> List[Token]`
  - `SentenceSegmenterSPI`: `split_sentences(text: str) -> List[Sentence]` および簡易文字列リスト取得 `split_text(text: str) -> List[str]`
  - `MorphologicalAnalyzerSPI`: `parse(text: str) -> List[Morpheme]`
  - `KeyphraseExtractionSPI`: `extract_keyphrases(text: str, top_k: int = 5) -> List[Tuple[str, float]]`
  - `DiscourseSummarizerSPI`: `summarize(text: str) -> Dict[str, str]`
  - `TopicClustererSPI`: `cluster(documents: Sequence[Dict[str, str]], num_clusters: Optional[int] = None) -> List[TopicCluster]`

### ステップ 3: `src/nlp/segmentation/academic_segmenter.py` の実装
1. **保護トークン置換辞書の整備**:
   - 略語リスト: `e.g.`, `i.e.`, `et al.`, `etc.`, `cf.`, `vs.`, `approx.`, `viz.`, `al.`
   - 図表・文献プレフィックス: `Fig.`, `Figs.`, `Table.`, `Ref.`, `Refs.`, `Sec.`, `Eq.`, `No.`, `Vol.`
   - 識別子・バージョン: `v1.0`, `CVE-202X-...`
2. **2フェーズ境界解析アルゴリズム**:
   - Phase A (Masking): 略語および引用符（`"..."`, `'...'`）内部のピリオドを一時的な安全プレースホルダー（例: `\uE000` 領域の文字）に置換。
   - Phase B (Splitting): 末尾記号 `[.!?]` に続く空白・改行境界で分割。
   - Phase C (Unmasking & Span Calculation): プレースホルダーを復元し、原文に対する正確な `Span(start, end)` と `Sentence` インスタンスを構築。
3. **安全装置**:
   - 最大入力文字長（`max_text_length: int = 1_000_000`）の超過チェック。

### ステップ 4: 既存モジュールとの後方互換性結合
- `src/pipeline/transformer/structured_summarizer.py` 内の `_split_into_sentences` を `AcademicSentenceSegmenter().split_text(text)` へ移行。
- 従来のシグネチャ `def _split_into_sentences(text: str) -> List[str]` および動作を 100% 維持。

### ステップ 5: 品質検証 & テストスイート
- 単体テスト `tests/nlp/test_core_protocols.py`: プロトコル適合性、データクラスの不変性、等価性、シリアライズ。
- 単体テスト `tests/nlp/test_academic_segmenter.py`:
  - `et al.` や `e.g.`、`Fig. 1` を含む複文学術アブストラクトの正確な分割。
  - カンマやクォート付き学術文の境界維持。
  - 極端な文字列に対する ReDoS 耐性テスト（ミリ秒単位で完了することを確認）。
- `make verify_quality` (または `make check`) を実行し、CC <= 3, mypy 0 エラー、pytest 100% を実証。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `src/nlp/core/tokens.py` に `Token`, `Span`, `Sentence`, `Morpheme`, `TopicCluster` がイミュータブルに定義されていること。
- [x] `src/nlp/core/protocols.py` に 6 つの SPI Protocols が `@runtime_checkable` として正しく定義されていること。
- [x] `AcademicSentenceSegmenter` が `SentenceSegmenterSPI` に適合し、略語保護付きで誤分割なく動作すること。
- [x] `src/pipeline/transformer/structured_summarizer.py` が内部で `AcademicSentenceSegmenter` を活用しつつ、既存テストが全て PASS すること。
- [x] `tests/nlp/` 配下に包括的なユニットテストが存在し、エッジケース・ReDoS耐性が実証されていること。
- [x] `xenon --max-absolute A` (CC <= 3) および `mypy --strict` の静的解析を 0 エラーでパスすること。

