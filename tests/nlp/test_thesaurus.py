"""Unit tests for SecurityThesaurus and StopWords."""

from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import is_stop_word


def test_thesaurus_japanese_lookup():
    """Verify English to Japanese translation lookup."""
    thesaurus = SecurityThesaurus()
    assert thesaurus.lookup_japanese("side-channel attack") == "サイドチャネル攻撃"
    assert thesaurus.lookup_japanese("prompt injection") == "プロンプトインジェクション"
    assert thesaurus.lookup_japanese("zero-trust") == "ゼロトラスト"
    assert thesaurus.lookup_japanese("nonexistent term") is None
    assert thesaurus.lookup_japanese("") is None


def test_thesaurus_synonyms_and_canonical():
    """Verify synonym expansion and canonical normalization."""
    thesaurus = SecurityThesaurus()
    syns = thesaurus.get_synonyms("side-channel attack")
    assert "サイドチャネル攻撃" in syns
    assert "side-channel attack" not in syns

    canonical = thesaurus.get_canonical_term("サイドチャネル攻撃")
    assert canonical == "side-channel attack"

    assert thesaurus.get_synonyms("") == ()
    assert thesaurus.get_canonical_term("unknown") == "unknown"


def test_thesaurus_all_vocabulary():
    """Verify all indexed vocabulary retrieval."""
    thesaurus = SecurityThesaurus()
    vocab = thesaurus.get_all_vocabulary()
    assert len(vocab) > 30
    assert "サイドチャネル攻撃" in vocab
    assert "side-channel attack" in vocab


def test_stop_words_filtering():
    """Verify stopword detection across languages and academic noise."""
    assert is_stop_word("the") is True
    assert is_stop_word("is") is True
    assert is_stop_word("において") is True
    assert is_stop_word("本論文") is True
    assert is_stop_word("propose") is True
    assert is_stop_word("side-channel") is False
    assert is_stop_word("cryptography") is False
    assert is_stop_word("") is True
