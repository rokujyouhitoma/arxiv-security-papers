"""Lexicon and Thesaurus package for NLP subsystem."""

from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import STOPWORDS, is_stop_word

__all__ = ["SecurityThesaurus", "STOPWORDS", "is_stop_word"]
