"""Structured 3-Point Academic Summarizer Module.

Synthesizes high-precision structured Japanese summaries from academic papers:
1. Threat & Vulnerability (背景・課題)
2. Proposed Method (提案手法・アプローチ)
3. Impact & Empirical Results (実証結果・セキュリティ影響)
Zero external dependencies. Fully compliant with DiscourseSummarizerSPI.
"""

from __future__ import annotations

import re
from typing import Callable, Dict, Optional, Tuple

from nlp.core.context import (
    _DEFAULT_SYNTHESIZER_RULES,
    SynthesizerRuleConfig,
    resolve_synthesizer_rules,
    resolve_thesaurus,
)
from nlp.core.protocols import DiscourseSummarizerSPI
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter
from nlp.summarization.discourse_parser import DiscourseRhetoricParser

# Backward-compatible module constants
KEYWORD_TRANSLATIONS: Tuple[Tuple[str, str], ...] = (
    _DEFAULT_SYNTHESIZER_RULES.keyword_translations
)
PHRASE_REPLACEMENTS: Tuple[Tuple[str, str], ...] = (
    _DEFAULT_SYNTHESIZER_RULES.phrase_replacements
)


def _apply_thesaurus_replacement(text: str, thesaurus: SecurityThesaurus) -> str:
    """Replace domain terms with canonical Japanese names using SecurityThesaurus."""
    res = text
    for term, ja_term in thesaurus.items():
        if len(term) > 3 and term.isascii() and ja_term != term:
            pattern = r"\b" + re.escape(term) + r"\b"
            res = re.sub(pattern, ja_term, res, flags=re.IGNORECASE)
    return res


def _apply_keyword_replacements(text: str, rules: SynthesizerRuleConfig) -> str:
    """Apply configured keyword replacements."""
    res = text
    for eng, jpn in rules.keyword_translations:
        res = re.sub(re.escape(eng), jpn, res, flags=re.IGNORECASE)
    return res


def _apply_academic_phrase_replacements(text: str, rules: SynthesizerRuleConfig) -> str:
    """Replace common academic English phrasing with Japanese equivalents."""
    res = text
    for eng_phrase, jpn_phrase in rules.phrase_replacements:
        res = re.sub(re.escape(eng_phrase), jpn_phrase, res, flags=re.IGNORECASE)
    return res


def _truncate_with_ellipsis(text: str, max_chars: int) -> str:
    """Truncate string to max_chars adding an ellipsis if exceeded."""
    if len(text) > max_chars:
        return text[: max_chars - 3] + "..."
    return text


def _translate_sentence_to_japanese(
    frag: Optional[str],
    default_text: str,
    thesaurus: SecurityThesaurus,
    rules: SynthesizerRuleConfig,
) -> str:
    """Convert an English sentence fragment into a concise Japanese summary element."""
    if not frag:
        return default_text

    res = _apply_thesaurus_replacement(frag, thesaurus)
    res = _apply_keyword_replacements(res, rules)
    res = _apply_academic_phrase_replacements(res, rules)
    return _truncate_with_ellipsis(res, 90)


def _format_executive_one_liner(
    prop_desc: str,
    impact_desc: str,
    rules: Optional[SynthesizerRuleConfig] = None,
) -> str:
    """Format single-line cohesive executive summary."""
    active_rules = resolve_synthesizer_rules(rules)
    one_liner = active_rules.executive_template.format(
        prop=prop_desc, impact=impact_desc
    )
    return _truncate_with_ellipsis(one_liner, 130)


def _build_descriptions(
    threat_sent: Optional[str],
    prop_sent: Optional[str],
    impact_sent: Optional[str],
    j_title: str,
    thesaurus: SecurityThesaurus,
    rules: SynthesizerRuleConfig,
) -> Tuple[str, str, str]:
    """Construct 3-point structured textual descriptions."""
    threat_desc = _translate_sentence_to_japanese(
        threat_sent,
        rules.threat_default_text,
        thesaurus,
        rules,
    )
    prop_default = rules.prop_default_template.format(j_title=j_title)
    prop_desc = _translate_sentence_to_japanese(
        prop_sent,
        prop_default,
        thesaurus,
        rules,
    )
    impact_desc = _translate_sentence_to_japanese(
        impact_sent,
        rules.impact_default_text,
        thesaurus,
        rules,
    )
    return threat_desc, prop_desc, impact_desc


class StructuredSynthesizer(DiscourseSummarizerSPI):
    """Generates 3-point structured executive summaries for security papers."""

    def __init__(
        self,
        segmenter: Optional[AcademicSentenceSegmenter] = None,
        parser: Optional[DiscourseRhetoricParser] = None,
        thesaurus: Optional[SecurityThesaurus] = None,
        title_translator: Optional[Callable[[str], str]] = None,
        rules: Optional[SynthesizerRuleConfig] = None,
    ) -> None:
        """Initialize StructuredSynthesizer with optional NLP components and rules."""
        self._segmenter = (
            segmenter
            if segmenter is not None
            else AcademicSentenceSegmenter(min_sentence_length=10)
        )
        self._parser = parser if parser is not None else DiscourseRhetoricParser()
        self._thesaurus = thesaurus
        self._title_translator = title_translator
        self._rules = rules

    def _get_thesaurus(self) -> SecurityThesaurus:
        """Resolve SecurityThesaurus via 3-tier fallback."""
        return resolve_thesaurus(self._thesaurus)

    def _get_rules(self) -> SynthesizerRuleConfig:
        """Resolve SynthesizerRuleConfig via 3-tier fallback."""
        return resolve_synthesizer_rules(self._rules)

    def _resolve_japanese_title(self, title: str, override: Optional[str]) -> str:
        """Resolve Japanese title using override, translator, or fallback."""
        if override:
            return override
        if not title:
            return "提案システム"
        if self._title_translator is not None:
            return self._title_translator(title)
        try:
            from pipeline.transformer.translator import translate_title_ja

            return translate_title_ja(title)
        except ImportError:
            return title

    def summarize(self, text: str) -> Dict[str, str]:
        """Synthesize structured summary mapping aspects to summaries (SPI)."""
        return self.summarize_paper(title="", abstract=text, clean_id="")

    def summarize_paper(
        self,
        title: str,
        abstract: str,
        clean_id: str = "",
        japanese_title: Optional[str] = None,
    ) -> Dict[str, str]:
        """Synthesize structured 3-point elements and single-line executive summary."""
        j_title = self._resolve_japanese_title(title, japanese_title)
        sentences = self._segmenter.split_text(abstract)
        threat_s, prop_s, impact_s = self._parser.select_aspect_sentences(sentences)

        thesaurus = self._get_thesaurus()
        rules = self._get_rules()

        threat_desc, prop_desc, impact_desc = _build_descriptions(
            threat_s, prop_s, impact_s, j_title, thesaurus, rules
        )

        return {
            "title_ja": j_title,
            "threat": threat_desc,
            "proposal": prop_desc,
            "impact": impact_desc,
            "executive_summary": _format_executive_one_liner(
                prop_desc, impact_desc, rules
            ),
        }
