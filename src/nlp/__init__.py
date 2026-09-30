"""NLP Subsystem: Natural Language Processing & Academic Text Analytics.

Zero-dependency, pure-Python foundational framework for sentence segmentation,
morphological analysis, keyphrase extraction, and discourse summarization.
"""

from nlp.clustering import DynamicTopicClusterer, TrendAnalyzer
from nlp.core.context import (
    CURRENT_ABBREVIATIONS,
    CURRENT_DISCOURSE_MARKERS,
    CURRENT_GRAMMAR_ENTRIES,
    CURRENT_SECURITY_TRANSLATIONS,
    CURRENT_STOPWORDS,
    CURRENT_SYNONYM_GROUPS,
    CURRENT_SYNTHESIZER_RULES,
    CURRENT_THESAURUS,
    CURRENT_TOPIC_DOMAINS,
    DiscourseMarkerConfig,
    SynthesizerRuleConfig,
    resolve_abbreviations,
    resolve_discourse_markers,
    resolve_grammar_entries,
    resolve_stopwords,
    resolve_synthesizer_rules,
    resolve_thesaurus,
    resolve_topic_domains,
)
from nlp.core.protocols import (
    DiscourseSummarizerSPI,
    KeyphraseExtractionSPI,
    MorphologicalAnalyzerSPI,
    SentenceSegmenterSPI,
    TokenizerSPI,
    TopicClustererSPI,
)
from nlp.core.tokens import Morpheme, Sentence, Span, Token, TopicCluster
from nlp.extraction import CValueExtractor, TextRankKeywordExtractor, extract_keyphrases
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import STOPWORDS, is_stop_word
from nlp.morphology.trie import PrefixTrie, TrieNode
from nlp.morphology.viterbi_tokenizer import PureMorphTokenizer
from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter
from nlp.summarization import (
    AspectScore,
    DiscourseRhetoricParser,
    SentenceAspect,
    StructuredSynthesizer,
)

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
    "TextRankKeywordExtractor",
    "CValueExtractor",
    "extract_keyphrases",
    "SentenceAspect",
    "AspectScore",
    "DiscourseRhetoricParser",
    "StructuredSynthesizer",
    "DynamicTopicClusterer",
    "TrendAnalyzer",
    "DiscourseMarkerConfig",
    "SynthesizerRuleConfig",
    "CURRENT_SECURITY_TRANSLATIONS",
    "CURRENT_SYNONYM_GROUPS",
    "CURRENT_THESAURUS",
    "CURRENT_STOPWORDS",
    "CURRENT_GRAMMAR_ENTRIES",
    "CURRENT_DISCOURSE_MARKERS",
    "CURRENT_SYNTHESIZER_RULES",
    "CURRENT_TOPIC_DOMAINS",
    "CURRENT_ABBREVIATIONS",
    "resolve_thesaurus",
    "resolve_stopwords",
    "resolve_grammar_entries",
    "resolve_discourse_markers",
    "resolve_synthesizer_rules",
    "resolve_topic_domains",
    "resolve_abbreviations",
]
