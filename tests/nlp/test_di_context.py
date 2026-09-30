"""Comprehensive unit tests for NLP Dependency Injection and Dynamic Scope.

Verifies:
1. Level 1: Constructor Injection (Explicit components and configs)
2. Level 2: Dynamic Scope Injection (pylisp.dynvar.dynamic_bind context)
3. Level 3: Default Fallback Resolution (Built-in constants & backward compatibility)
4. Async-Safe Concurrency (Task isolation without context leakage)
5. Generator Guard & Security Validation (ReDoS defense, immutability)
"""

from __future__ import annotations

import asyncio
from dataclasses import FrozenInstanceError
from typing import Any

import pytest

from nlp.clustering.topic_model import DynamicTopicClusterer
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
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import is_stop_word
from nlp.morphology.viterbi_tokenizer import PureMorphTokenizer
from nlp.segmentation.academic_segmenter import AcademicSentenceSegmenter
from nlp.summarization.discourse_parser import DiscourseRhetoricParser
from nlp.summarization.structured_synthesizer import StructuredSynthesizer
from pylisp.dynvar import dynamic_bind

# =========================================================================
# 1. Level 1: Constructor Injection Tests
# =========================================================================


def test_constructor_di_thesaurus() -> None:
    """Verify SecurityThesaurus with explicit custom translations and synonyms."""
    custom_trans = {"oncology": "腫瘍学", "biomarker": "バイオマーカー"}
    custom_groups = (("oncology", "cancer study", "腫瘍学"),)
    thesaurus = SecurityThesaurus(
        translations=custom_trans, synonym_groups=custom_groups
    )

    assert thesaurus.lookup_japanese("oncology") == "腫瘍学"
    assert thesaurus.lookup_japanese("biomarker") == "バイオマーカー"
    assert "cancer study" in thesaurus.get_synonyms("oncology")
    # Verify default terms are not in the custom instance
    assert thesaurus.lookup_japanese("side-channel attack") is None


def test_constructor_di_academic_segmenter() -> None:
    """Verify AcademicSentenceSegmenter with custom abbreviation injection."""
    custom_abbrs = (("diag.", "diag\ue001"),)
    segmenter = AcademicSentenceSegmenter(abbreviations=custom_abbrs)

    text = "The diag. was confirmed. Next step follows."
    sentences = segmenter.split_text(text)
    assert len(sentences) == 2
    assert sentences[0] == "The diag. was confirmed."


def test_constructor_di_viterbi_tokenizer() -> None:
    """Verify PureMorphTokenizer with custom grammar and thesaurus."""
    custom_grammar = (("テスト語", 10, "名詞(カスタム)"),)
    custom_thesaurus = SecurityThesaurus(translations={"customterm": "カスタム語"})
    tokenizer = PureMorphTokenizer(
        grammar_entries=custom_grammar, thesaurus=custom_thesaurus
    )

    tokens = tokenizer.tokenize("テスト語")
    assert len(tokens) == 1
    assert tokens[0].text == "テスト語"
    assert tokens[0].tag == "名詞(カスタム)"


def test_constructor_di_discourse_parser() -> None:
    """Verify DiscourseRhetoricParser with custom DiscourseMarkerConfig."""
    custom_cfg = DiscourseMarkerConfig(
        threat_markers=("pathology",),
        proposal_markers=("therapy",),
        impact_markers=("cure",),
        negation_patterns=(r"\bno\b",),
        prior_work_patterns=(r"\bold study\b",),
        modality_boosters=(r"\bsignificantly\b",),
    )
    parser = DiscourseRhetoricParser(marker_config=custom_cfg)

    sentences = [
        "A severe pathology was observed in the tissue.",
        "We introduce a targeted therapy for the condition.",
        "The treatment achieved a complete cure significantly.",
    ]
    threat, prop, impact = parser.select_aspect_sentences(sentences)
    assert threat == sentences[0]
    assert prop == sentences[1]
    assert impact == sentences[2]


def test_constructor_di_structured_synthesizer() -> None:
    """Verify StructuredSynthesizer with custom SynthesizerRuleConfig."""
    custom_rules = SynthesizerRuleConfig(
        keyword_translations=(("quantum", "クォンタム"),),
        phrase_replacements=(("we propose", "独自考案した"),),
        threat_default_text="独自課題",
        prop_default_template="{j_title}の独自提案",
        impact_default_text="独自実証",
        executive_template="【独自】{prop}により{impact}。",
    )
    synthesizer = StructuredSynthesizer(rules=custom_rules)
    result = synthesizer.summarize_paper(
        title="Quantum Algorithm",
        abstract="We propose a quantum method.",
        japanese_title="量子アルゴリズム",
    )

    assert "【独自】" in result["executive_summary"]
    assert "独自考案した a クォンタム method." in result["proposal"]
    assert result["threat"] == "独自課題"


def test_constructor_di_topic_clusterer() -> None:
    """Verify DynamicTopicClusterer with custom domain mapping."""
    custom_domains = (("バイオインフォマティクス", ("genomics", "crispr")),)
    clusterer = DynamicTopicClusterer(domain_map=custom_domains)
    doc = {
        "title": "CRISPR-Cas9 Analysis",
        "abstract": "We evaluate genomics data using crispr techniques.",
        "clean_id": "bio.0001",
    }
    clusters = clusterer.cluster([doc])
    assert len(clusters) == 1
    assert clusters[0].label == "バイオインフォマティクス"


# =========================================================================
# 2. Level 2: Dynamic Scope Injection Tests (dynamic_bind)
# =========================================================================


def test_dynamic_bind_stopwords() -> None:
    """Verify is_stop_word adapts dynamically inside dynamic_bind scope."""
    word = "customuniquetoken"
    assert not is_stop_word(word)

    with dynamic_bind({CURRENT_STOPWORDS: frozenset({word})}):
        assert is_stop_word(word)
        # Built-in stopword should not be active in this narrow context
        assert not is_stop_word("the")

    # Scope rewind check
    assert not is_stop_word(word)
    assert is_stop_word("the")


def test_dynamic_bind_thesaurus_and_synthesizer() -> None:
    """Verify StructuredSynthesizer uses dynamic scope without constructor args."""
    custom_thesaurus = SecurityThesaurus(
        translations={"cyber": "電脳", "attack": "急襲"}
    )
    custom_rules = SynthesizerRuleConfig(
        keyword_translations=(("cyber", "電脳"),),
        phrase_replacements=(("we present", "電脳開示し"),),
        threat_default_text="電脳空間の危機",
        prop_default_template="{j_title}の電脳基盤",
        impact_default_text="急襲阻止の達成",
        executive_template="【電脳要約】{prop}::{impact}",
    )

    synthesizer = StructuredSynthesizer()

    with dynamic_bind(
        {
            CURRENT_THESAURUS: custom_thesaurus,
            CURRENT_SYNTHESIZER_RULES: custom_rules,
        }
    ):
        result = synthesizer.summarize_paper(
            title="Cyber Defense",
            abstract="We present cyber attack countermeasures.",
            japanese_title="サイバー防御",
        )
        assert result["executive_summary"].startswith("【電脳要約】")
        assert "電脳開示し" in result["proposal"]
        assert result["threat"] == "電脳空間の危機"

    # Outside dynamic scope, default rules must return
    default_result = synthesizer.summarize_paper(
        title="Cyber Defense",
        abstract="We present cyber attack countermeasures.",
        japanese_title="サイバー防御",
    )
    assert default_result["executive_summary"].startswith("【提案】")


def test_dynamic_bind_academic_segmenter() -> None:
    """Verify AcademicSentenceSegmenter adapts to dynamic abbreviations."""
    segmenter = AcademicSentenceSegmenter()
    text = "Refer to ex. 1 for details. Step follows."

    with dynamic_bind({CURRENT_ABBREVIATIONS: (("ex.", "ex\ue001"),)}):
        sentences = segmenter.split_text(text)
        assert len(sentences) == 2
        assert sentences[0] == "Refer to ex. 1 for details."


def test_dynamic_bind_discourse_parser() -> None:
    """Verify DiscourseRhetoricParser uses dynamically bound marker config."""
    custom_markers = DiscourseMarkerConfig(
        threat_markers=("danger",),
        proposal_markers=("solution",),
        impact_markers=("success",),
        negation_patterns=(),
        prior_work_patterns=(),
        modality_boosters=(),
    )
    parser = DiscourseRhetoricParser()

    with dynamic_bind({CURRENT_DISCOURSE_MARKERS: custom_markers}):
        scores = parser.parse_sentences(["A huge danger emerged."])
        assert scores[0].threat > 0.0


def test_dynamic_bind_topic_clusterer() -> None:
    """Verify DynamicTopicClusterer uses dynamically bound domain mapping."""
    custom_domains = (("宇宙工学", ("satellite", "orbit")),)
    clusterer = DynamicTopicClusterer()

    with dynamic_bind({CURRENT_TOPIC_DOMAINS: custom_domains}):
        doc = {
            "title": "Satellite Security",
            "abstract": "We analyze satellite communication orbit vulnerabilities.",
            "clean_id": "sat.001",
        }
        clusters = clusterer.cluster([doc])
        assert len(clusters) == 1
        assert clusters[0].label == "宇宙工学"


def test_dynamic_bind_translations_and_grammar() -> None:
    """Verify CURRENT_SECURITY_TRANSLATIONS and CURRENT_GRAMMAR_ENTRIES in dynamic_bind."""
    custom_trans = {"testvuln": "試験的脆弱性"}
    custom_grammar = (("試験単語", 5, "名詞(試験)"),)
    custom_synonyms = (("testvuln", "testflaw"),)

    with dynamic_bind(
        {
            CURRENT_SECURITY_TRANSLATIONS: custom_trans,
            CURRENT_GRAMMAR_ENTRIES: custom_grammar,
            CURRENT_SYNONYM_GROUPS: custom_synonyms,
        }
    ):
        thesaurus = SecurityThesaurus()
        assert thesaurus.lookup_japanese("testvuln") == "試験的脆弱性"
        assert "testflaw" in thesaurus.get_synonyms("testvuln")

        tokenizer = PureMorphTokenizer()
        tokens = tokenizer.tokenize("試験単語")
        assert len(tokens) == 1
        assert tokens[0].tag == "名詞(試験)"


# =========================================================================
# 3. Level 3: Default Fallback Resolution Tests
# =========================================================================


def test_default_fallback_resolvers() -> None:
    """Verify resolvers return defaults when no explicit or dynamic scope active."""
    thesaurus = resolve_thesaurus()
    assert isinstance(thesaurus, SecurityThesaurus)
    assert thesaurus.lookup_japanese("side-channel attack") == "サイドチャネル攻撃"

    stopwords = resolve_stopwords()
    assert "the" in stopwords
    assert "は" in stopwords

    grammar = resolve_grammar_entries()
    assert len(grammar) > 0

    markers = resolve_discourse_markers()
    assert "vulnerab" in markers.threat_markers

    rules = resolve_synthesizer_rules()
    assert len(rules.keyword_translations) > 0

    domains = resolve_topic_domains()
    assert len(domains) > 0

    abbrs = resolve_abbreviations()
    assert any(a[0] == "et al." for a in abbrs)


# =========================================================================
# 4. Async-Safe Concurrency & Task Isolation Tests
# =========================================================================


def test_async_concurrency_isolation() -> None:
    """Verify dynamic_bind in parallel coroutines remains isolated across tasks."""

    async def task_a() -> str:
        rules_a = SynthesizerRuleConfig(
            keyword_translations=(),
            phrase_replacements=(),
            executive_template="【TASK_A】{prop}::{impact}",
        )
        with dynamic_bind({CURRENT_SYNTHESIZER_RULES: rules_a}):
            await asyncio.sleep(0.02)
            synth = StructuredSynthesizer()
            res = synth.summarize_paper("Title", "Abstract", japanese_title="A")
            return res["executive_summary"]

    async def task_b() -> str:
        rules_b = SynthesizerRuleConfig(
            keyword_translations=(),
            phrase_replacements=(),
            executive_template="【TASK_B】{prop}::{impact}",
        )
        with dynamic_bind({CURRENT_SYNTHESIZER_RULES: rules_b}):
            await asyncio.sleep(0.02)
            synth = StructuredSynthesizer()
            res = synth.summarize_paper("Title", "Abstract", japanese_title="B")
            return res["executive_summary"]

    async def runner() -> tuple[str, str]:
        return await asyncio.gather(task_a(), task_b())

    out_a, out_b = asyncio.run(runner())
    assert out_a.startswith("【TASK_A】")
    assert out_b.startswith("【TASK_B】")


# =========================================================================
# 5. Security & Immutability Validation Tests
# =========================================================================


def test_discourse_marker_config_max_length_guard() -> None:
    """Verify ReDoS threat mitigation via max length validation in DiscourseMarkerConfig."""
    too_long = "a" * 257
    with pytest.raises(ValueError, match="Pattern exceeds maximum allowed length"):
        DiscourseMarkerConfig(
            threat_markers=(too_long,),
            proposal_markers=(),
            impact_markers=(),
            negation_patterns=(),
            prior_work_patterns=(),
            modality_boosters=(),
        )


def test_configs_are_immutable() -> None:
    """Verify frozen dataclass prevents in-place mutation."""
    markers = resolve_discourse_markers()
    with pytest.raises(FrozenInstanceError):
        markers.threat_markers = ("mutated",)  # type: ignore[misc]

    rules = resolve_synthesizer_rules()
    with pytest.raises(FrozenInstanceError):
        rules.executive_template = "mutated"  # type: ignore[misc]


def test_generator_abuse_detection() -> None:
    """Verify dynamic_bind rejects usage inside generators to prevent context leakage."""

    def generator_under_test() -> Any:
        with dynamic_bind({CURRENT_STOPWORDS: frozenset()}):
            yield 1

    gen = generator_under_test()
    with pytest.raises(
        RuntimeError,
        match="dynamic_bind cannot be safely used directly inside a generator",
    ):
        next(gen)
