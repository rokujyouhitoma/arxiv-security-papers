"""Discourse Rhetoric and Sentence Aspect Analysis Module.

Analyzes discourse rhetoric across academic security abstracts using:
1. Multi-aspect scoring (Threat/Vulnerability, Proposal, Impact)
2. Negation and counter-argument detection (suppresses false proposal claims)
3. Prior work differentiation (identifies existing studies vs novelty)
4. Modality and empirical strength weighting
Zero external dependencies.
"""

import re
from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, Sequence, Set, Tuple

from nlp.core.context import (
    _DEFAULT_DISCOURSE_MARKERS,
    DiscourseMarkerConfig,
    resolve_discourse_markers,
)


class SentenceAspect(str, Enum):
    """Aspect category of an academic sentence."""

    THREAT = "threat"
    PROPOSAL = "proposal"
    IMPACT = "impact"


@dataclass(frozen=True, slots=True)
class AspectScore:
    """Multi-aspect scores and rhetorical features for a single sentence."""

    sentence: str
    threat: float
    proposal: float
    impact: float
    is_negated: bool = False
    is_prior_work: bool = False
    modality_score: float = 1.0

    @property
    def dominant_aspect(self) -> SentenceAspect:
        """Return the aspect with the highest score."""
        if self.threat >= self.proposal and self.threat >= self.impact:
            return SentenceAspect.THREAT
        if self.proposal >= self.impact:
            return SentenceAspect.PROPOSAL
        return SentenceAspect.IMPACT


# Backward-compatible default markers
THREAT_MARKERS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.threat_markers
PROPOSAL_MARKERS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.proposal_markers
IMPACT_MARKERS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.impact_markers
NEGATION_PATTERNS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.negation_patterns
PRIOR_WORK_PATTERNS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.prior_work_patterns
MODALITY_BOOSTERS: Tuple[str, ...] = _DEFAULT_DISCOURSE_MARKERS.modality_boosters


def _matches_any_pattern(text: str, patterns: Sequence[str]) -> bool:
    """Check if any compiled or literal pattern matches text."""
    lower = text.lower()
    for pat in patterns:
        if re.search(pat, lower):
            return True
    return False


def _count_marker_matches(text: str, markers: Sequence[str]) -> int:
    """Count occurrences of substring markers in text."""
    lower = text.lower()
    return sum(1 for m in markers if m in lower)


def _evaluate_modality(text: str, config: DiscourseMarkerConfig) -> float:
    """Compute empirical strength multiplier."""
    boosts = sum(1 for pat in config.modality_boosters if re.search(pat, text.lower()))
    return 1.0 + min(boosts * 0.5, 2.0)


def _compute_raw_aspect_scores(
    sentence: str, config: DiscourseMarkerConfig
) -> Tuple[float, float, float]:
    """Calculate raw keyword match counts for aspects."""
    t_raw = float(_count_marker_matches(sentence, config.threat_markers))
    p_raw = float(_count_marker_matches(sentence, config.proposal_markers))
    i_raw = float(_count_marker_matches(sentence, config.impact_markers))
    return t_raw, p_raw, i_raw


def _apply_position_bias(
    raw_scores: Tuple[float, float, float], idx: int, total: int
) -> Tuple[float, float, float]:
    """Adjust aspect scores based on sentence position in abstract."""
    t_score, p_score, i_score = raw_scores
    if idx == 0:
        t_score += 1.5
    elif 0 < idx < total - 1:
        p_score += 1.0
    if idx == total - 1:
        i_score += 1.5
    return t_score, p_score, i_score


def _adjust_for_negation(
    p_score: float, t_score: float, is_negated: bool
) -> Tuple[float, float]:
    """Dampen proposal score and elevate threat score if sentence contains negation."""
    if not is_negated:
        return p_score, t_score
    adjusted_p = p_score * 0.05
    adjusted_t = t_score + 1.0
    return adjusted_p, adjusted_t


def _adjust_for_prior_work(
    p_score: float, t_score: float, is_prior: bool
) -> Tuple[float, float]:
    """Shift proposal score to threat if sentence describes prior work."""
    if not is_prior:
        return p_score, t_score
    adjusted_p = p_score * 0.1
    adjusted_t = t_score + 1.5
    return adjusted_p, adjusted_t


def _score_single_sentence(
    sentence: str, idx: int, total: int, config: DiscourseMarkerConfig
) -> AspectScore:
    """Analyze rhetorical aspect and modifiers for one sentence."""
    raw = _compute_raw_aspect_scores(sentence, config)
    t_pos, p_pos, i_pos = _apply_position_bias(raw, idx, total)

    is_neg = _matches_any_pattern(sentence, config.negation_patterns)
    p_neg, t_neg = _adjust_for_negation(p_pos, t_pos, is_neg)

    is_prior = _matches_any_pattern(sentence, config.prior_work_patterns)
    p_final, t_final = _adjust_for_prior_work(p_neg, t_neg, is_prior)

    mod_weight = _evaluate_modality(sentence, config)
    i_final = i_pos * mod_weight

    return AspectScore(
        sentence=sentence,
        threat=t_final,
        proposal=p_final,
        impact=i_final,
        is_negated=is_neg,
        is_prior_work=is_prior,
        modality_score=mod_weight,
    )


def _find_best_sentence(
    scored: Sequence[AspectScore],
    aspect: SentenceAspect,
    exclude: Set[str],
) -> Optional[str]:
    """Find the highest-scoring sentence for an aspect, ignoring excluded sentences."""
    best_sent: Optional[str] = None
    best_score = -1.0

    for item in scored:
        if item.sentence in exclude:
            continue
        val = getattr(item, aspect.value)
        if val > best_score:
            best_score = val
            best_sent = item.sentence

    return best_sent


class DiscourseRhetoricParser:
    """Rhetorical discourse parser with negation, prior-work, and modality filters."""

    def __init__(self, marker_config: Optional[DiscourseMarkerConfig] = None) -> None:
        """Initialize parser with optional DI marker configuration."""
        self._marker_config = marker_config

    def _get_marker_config(self) -> DiscourseMarkerConfig:
        """Resolve active DiscourseMarkerConfig via 3-tier fallback."""
        return resolve_discourse_markers(self._marker_config)

    def parse_sentences(self, sentences: Sequence[str]) -> List[AspectScore]:
        """Parse all sentences into detailed AspectScore objects."""
        total = len(sentences)
        cfg = self._get_marker_config()
        return [
            _score_single_sentence(s, idx, total, cfg)
            for idx, s in enumerate(sentences)
        ]

    def select_aspect_sentences(
        self, sentences: Sequence[str]
    ) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """Select distinct top sentences for Threat, Proposal, and Impact."""
        if not sentences:
            return None, None, None

        scored = self.parse_sentences(sentences)
        chosen: Set[str] = set()

        prop = _find_best_sentence(scored, SentenceAspect.PROPOSAL, chosen)
        if prop:
            chosen.add(prop)

        threat = _find_best_sentence(scored, SentenceAspect.THREAT, chosen)
        if threat:
            chosen.add(threat)

        impact = _find_best_sentence(scored, SentenceAspect.IMPACT, chosen)

        return threat, prop, impact
