"""Structured Multi-Stage Summarizer Module.

Parses academic paper abstracts using discourse rhetorical markers to
extract and synthesize 3-point structured summaries:
1. Threat & Vulnerability (背景・課題)
2. Proposed Method (提案手法・アプローチ)
3. Impact & Empirical Results (実証結果・セキュリティ影響)
Designed for future promotion to `src/nlp/` generic package.
"""

import re
from typing import Dict, List, Optional, Tuple

from pipeline.transformer.translator import translate_title_ja

# Discourse Markers for rhetoric classification
THREAT_MARKERS = [
    "vulnerab",
    "threat",
    "attack",
    "exploit",
    "leak",
    "risk",
    "flaw",
    "problem",
    "challenge",
    "bypass",
    "poison",
    "jailbreak",
    "eavesdrop",
    "tamper",
    "side-channel",
    "fault injection",
    "malware",
    "compromise",
    "insecurity",
]

PROPOSAL_MARKERS = [
    "propose",
    "present",
    "introduce",
    "develop",
    "design",
    "framework",
    "architecture",
    "mechanism",
    "method",
    "approach",
    "scheme",
    "protocol",
    "system",
    "tool",
    "algorithm",
    "pipeline",
]

IMPACT_MARKERS = [
    "result",
    "evaluat",
    "demonstrat",
    "experiment",
    "show",
    "achiev",
    "outperform",
    "effective",
    "accuracy",
    "overhead",
    "mitigat",
    "reduc",
    "prevent",
    "success rate",
]

KEYWORD_TRANSLATIONS = [
    ("prompt injection", "プロンプトインジェクション"),
    ("jailbreak", "ジェイルブレイク"),
    ("side-channel", "サイドチャネル攻撃"),
    ("fault injection", "フォールト注入"),
    ("zero-trust", "ゼロトラスト"),
    ("differential privacy", "差分プライバシー"),
    ("smart contract", "スマートコントラクト"),
    ("malware", "マルウェア"),
    ("rowhammer", "RowHammer"),
    ("quantum", "量子"),
    ("cryptography", "暗号技術"),
    ("vulnerability", "脆弱性"),
]


def _split_into_sentences(text: str) -> List[str]:
    """Splits an abstract into individual sentences."""
    if not text:
        return []
    cleaned = text.replace("\n", " ").strip()
    sentences = re.split(r"(?<=[.!?])\s+", cleaned)
    return [s.strip() for s in sentences if len(s.strip()) > 10]


def _score_sentence(sentence: str, markers: List[str]) -> int:
    """Calculates match score for rhetorical markers."""
    lower = sentence.lower()
    return sum(1 for m in markers if m in lower)


def _compute_position_scores(
    sentence: str, idx: int, total_len: int
) -> Tuple[int, int, int]:
    """Computes threat, proposal, and impact scores for a single sentence."""
    t_score = _score_sentence(sentence, THREAT_MARKERS) + (1 if idx == 0 else 0)
    p_score = _score_sentence(sentence, PROPOSAL_MARKERS) + (
        1 if 0 < idx < total_len - 1 else 0
    )
    i_score = _score_sentence(sentence, IMPACT_MARKERS) + (
        1 if idx == total_len - 1 else 0
    )
    return t_score, p_score, i_score


def _classify_sentences(
    sentences: List[str],
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Classifies sentences into Threat, Proposal, and Impact."""
    threat_sent: Optional[str] = None
    proposal_sent: Optional[str] = None
    impact_sent: Optional[str] = None

    max_t, max_p, max_i = 0, 0, 0
    total = len(sentences)

    for idx, s in enumerate(sentences):
        t_score, p_score, i_score = _compute_position_scores(s, idx, total)

        if t_score > max_t:
            max_t = t_score
            threat_sent = s
        if p_score > max_p:
            max_p = p_score
            proposal_sent = s
        if i_score > max_i:
            max_i = i_score
            impact_sent = s

    return threat_sent, proposal_sent, impact_sent


def _translate_fragment_to_japanese(frag: Optional[str], default_text: str) -> str:
    """Translates or summarizes an English fragment into clean Japanese context."""
    if not frag:
        return default_text

    res = frag
    for eng, jpn in KEYWORD_TRANSLATIONS:
        res = re.sub(re.escape(eng), jpn, res, flags=re.IGNORECASE)

    res = res.replace("In this paper, we", "本論文では")
    res = res.replace("We propose", "新規に提案し")
    res = res.replace("We present", "提示し")
    if len(res) > 90:
        return res[:87] + "..."
    return res


def _format_one_liner(prop_desc: str, impact_desc: str) -> str:
    """Formats 1-line cohesive executive summary."""
    one_liner = f"【提案】{prop_desc}。実証評価により{impact_desc}。"
    if len(one_liner) > 130:
        return one_liner[:127] + "..."
    return one_liner


def _build_summary_descriptions(
    sentences: List[str], j_title: str
) -> Tuple[str, str, str]:
    """Generates 3-point structured textual descriptions."""
    threat_raw, prop_raw, impact_raw = _classify_sentences(sentences)
    threat_desc = (
        _translate_fragment_to_japanese(
            threat_raw, "対象ドメインのセキュリティ脅威と脆弱性"
        )
        if threat_raw
        else "既存システムのセキュリティ境界における脆弱性課題"
    )
    prop_desc = (
        _translate_fragment_to_japanese(prop_raw, f"{j_title}の手法")
        if prop_raw
        else f"{j_title}の提案フレームワーク"
    )
    impact_desc = (
        _translate_fragment_to_japanese(
            impact_raw, "実証実験による有効性と安全性の検証"
        )
        if impact_raw
        else "実験的評価による防御性能と攻撃耐性の実証"
    )
    return threat_desc, prop_desc, impact_desc


class StructuredSummarizer:
    """Generates 3-point structured executive summaries for security papers."""

    def summarize(
        self,
        title: str,
        abstract: str,
        clean_id: str,
        japanese_title: Optional[str] = None,
    ) -> Dict[str, str]:
        """Synthesizes structured 3-point elements and single-line executive summary."""
        j_title = japanese_title or translate_title_ja(title)
        sentences = _split_into_sentences(abstract)
        (
            threat_desc,
            prop_desc,
            impact_desc,
        ) = _build_summary_descriptions(sentences, j_title)

        return {
            "title_ja": j_title,
            "threat": threat_desc,
            "proposal": prop_desc,
            "impact": impact_desc,
            "executive_summary": _format_one_liner(prop_desc, impact_desc),
        }


def generate_structured_summary(
    title: str,
    abstract: str,
    clean_id: str,
    japanese_title: Optional[str] = None,
) -> Dict[str, str]:
    """Convenience helper to generate structured 3-point executive summary."""
    summarizer = StructuredSummarizer()
    return summarizer.summarize(
        title=title,
        abstract=abstract,
        clean_id=clean_id,
        japanese_title=japanese_title,
    )
