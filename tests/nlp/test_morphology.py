"""Unit tests for PureMorphTokenizer and search integration."""

import time

from nlp.core.protocols import MorphologicalAnalyzerSPI, TokenizerSPI
from nlp.morphology.viterbi_tokenizer import PureMorphTokenizer
from search.core.analysis.tokenizer import MorphologyTokenizer, StandardTokenizer


def test_pure_morph_implements_spi():
    """Verify SPI compliance."""
    tokenizer = PureMorphTokenizer()
    assert isinstance(tokenizer, MorphologicalAnalyzerSPI)
    assert isinstance(tokenizer, TokenizerSPI)


def test_security_compound_segmentation():
    """Verify security domain keyphrases are segmented as unified tokens."""
    tokenizer = PureMorphTokenizer()
    text = "サイドチャネル攻撃とプロンプトインジェクションの脅威を分析する。"
    tokens = tokenizer.tokenize(text)
    token_texts = [t.text for t in tokens]

    assert "サイドチャネル攻撃" in token_texts
    assert "プロンプトインジェクション" in token_texts
    assert "脅威" in token_texts


def test_bilingual_mixed_segmentation():
    """Verify bilingual mixed prose segmentation."""
    tokenizer = PureMorphTokenizer()
    text = "SpecShieldはSpectre脆弱性を防ぐ新しい手法である。"
    tokens = tokenizer.tokenize(text)
    token_texts = [t.text for t in tokens]

    assert "SpecShield" in token_texts
    assert "Spectre" in token_texts
    assert "脆弱性" in token_texts
    assert "手法" in token_texts


def test_token_spans_accuracy():
    """Verify character offset spans match source text."""
    tokenizer = PureMorphTokenizer()
    text = "量子鍵配送と暗号技術"
    tokens = tokenizer.tokenize(text)

    for t in tokens:
        assert text[t.span.start : t.span.end] == t.text

    assert tokens[0].text == "量子鍵配送"
    assert tokens[1].text == "と"
    assert tokens[2].text == "暗号技術"


def test_parse_morphemes():
    """Verify Morpheme conversion and part-of-speech tags."""
    tokenizer = PureMorphTokenizer()
    morphemes = tokenizer.parse("ゼロトラストモデル")
    assert len(morphemes) >= 1
    assert morphemes[0].surface == "ゼロトラスト"
    assert morphemes[0].pos == "名詞(セキュリティ)"


def test_unknown_words_and_redos_resilience():
    """Verify robust handling of unknown characters without explosive backtracking."""
    tokenizer = PureMorphTokenizer()
    pathological = "XYZ" * 2000 + " 正常な文。"
    start = time.perf_counter()
    tokens = tokenizer.tokenize(pathological)
    elapsed = time.perf_counter() - start

    assert elapsed < 0.5, f"Execution took too long ({elapsed:.3f}s)"
    assert len(tokens) > 0


def test_search_standard_tokenizer_morphology_integration():
    """Verify StandardTokenizer with use_morphology=True segments CJK into terms."""
    std_bigram = StandardTokenizer(use_morphology=False)
    tokens_bg = std_bigram.tokenize("マルウェア分類手法")
    bg_texts = [t.text for t in tokens_bg]
    # Bigram produces 2-char slices
    assert "マル" in bg_texts

    std_morph = StandardTokenizer(use_morphology=True)
    tokens_morph = std_morph.tokenize("マルウェア分類手法")
    morph_texts = [t.text for t in tokens_morph]
    assert "マルウェア" in morph_texts


def test_search_morphology_tokenizer():
    """Verify dedicated MorphologyTokenizer for search pipelines."""
    search_tokenizer = MorphologyTokenizer()
    tokens = search_tokenizer.tokenize("フォールト注入攻撃の検出")
    texts = [t.text for t in tokens]
    assert "フォールト注入攻撃" in texts
