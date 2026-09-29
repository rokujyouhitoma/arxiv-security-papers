"""NLP Subsystem: Natural Language Processing & Academic Text Analytics.

Zero-dependency, pure-Python foundational framework for sentence segmentation,
morphological analysis, keyphrase extraction, and discourse summarization.
"""

from nlp.core.protocols import (
    DiscourseSummarizerSPI,
    KeyphraseExtractionSPI,
    MorphologicalAnalyzerSPI,
    SentenceSegmenterSPI,
    TokenizerSPI,
    TopicClustererSPI,
)
from nlp.core.tokens import Morpheme, Sentence, Span, Token, TopicCluster
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import STOPWORDS, is_stop_word
from nlp.morphology.trie import PrefixTrie, TrieNode
from nlp.morphology.viterbi_tokenizer import PureMorphTokenizer
from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter

__all__ = [
    "Span",
    "Token",
    "Sentence",
    "Morpheme",
    "TopicCluster",
    "TokenizerSPI",
    "SentenceSegmenterSPI",
    "MorphologicalAnalyzerSPI",
    "KeyphraseExtractionSPI",
    "DiscourseSummarizerSPI",
    "TopicClustererSPI",
    "AcademicSentenceSegmenter",
    "PrefixTrie",
    "TrieNode",
    "PureMorphTokenizer",
    "SecurityThesaurus",
    "STOPWORDS",
    "is_stop_word",
]
