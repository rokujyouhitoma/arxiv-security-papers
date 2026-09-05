#!/usr/bin/env python3
"""
Vocabulary & Context-Driven ATT&CK Technique Inference Engine.
Infers MITRE ATT&CK techniques, tactics, and research focus (offensive vs defensive)
from paper titles, abstracts, and full texts.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple

from ontology.rule_registry import EdgeInferenceRuleRegistry

# Regex pattern for direct ATT&CK Technique ID detection
TECHNIQUE_ID_REGEX = re.compile(r"\b(T\d{4}(?:\.\d{3})?)\b", re.IGNORECASE)

# Keywords indicating research focus
OFFENSIVE_KEYWORDS: Set[str] = {
    "exploit",
    "attack",
    "offensive",
    "adversary",
    "bypass",
    "vulnerability",
    "poc",
    "proof of concept",
    "payload",
    "zero-day",
    "weaponize",
    "jailbreak",
    "prompt injection",
}

DEFENSIVE_KEYWORDS: Set[str] = {
    "defense",
    "mitigate",
    "mitigation",
    "countermeasure",
    "detection",
    "detector",
    "protect",
    "firewall",
    "hardening",
    "sandbox",
    "verification",
    "guardrail",
}

# Built-in curated catalog of prevalent enterprise techniques
BUILTIN_TECHNIQUE_CATALOG: Dict[str, Dict[str, Any]] = {
    "T1190": {
        "name": "Exploit Public-Facing Application",
        "tactic": "initial-access",
        "keywords": [
            "rce",
            "remote code execution",
            "sql injection",
            "ssrf",
            "buffer overflow",
        ],
    },
    "T1566": {
        "name": "Phishing",
        "tactic": "initial-access",
        "keywords": [
            "phishing",
            "spearphishing",
            "social engineering",
            "credential harvesting",
        ],
    },
    "T1059": {
        "name": "Command and Scripting Interpreter",
        "tactic": "execution",
        "keywords": [
            "powershell",
            "bash",
            "python execution",
            "command injection",
            "shellcode",
        ],
    },
    "T1203": {
        "name": "Exploitation for Client Execution",
        "tactic": "execution",
        "keywords": [
            "browser exploit",
            "pdf exploit",
            "client-side execution",
            "heap spray",
        ],
    },
    "T1068": {
        "name": "Exploitation for Privilege Escalation",
        "tactic": "privilege-escalation",
        "keywords": [
            "privilege escalation",
            "lpe",
            "root access",
            "kernel exploit",
            "token abuse",
        ],
    },
    "T1027": {
        "name": "Obfuscated Files or Information",
        "tactic": "defense-evasion",
        "keywords": [
            "obfuscation",
            "packer",
            "encoding",
            "anti-analysis",
            "polymorphic",
        ],
    },
    "T1036": {
        "name": "Masquerading",
        "tactic": "defense-evasion",
        "keywords": [
            "masquerading",
            "fake certificate",
            "typosquatting",
            "process hollowing",
        ],
    },
    "T1110": {
        "name": "Brute Force",
        "tactic": "credential-access",
        "keywords": [
            "brute force",
            "credential stuffing",
            "password guessing",
            "dictionary attack",
        ],
    },
    "T1003": {
        "name": "OS Credential Dumping",
        "tactic": "credential-access",
        "keywords": [
            "lsass",
            "credential dumping",
            "mimikatz",
            "shadow copy",
            "ntlm hash",
        ],
    },
    "T1082": {
        "name": "System Information Discovery",
        "tactic": "discovery",
        "keywords": [
            "fingerprinting",
            "system discovery",
            "reconnaissance",
            "hardware survey",
        ],
    },
    "T1210": {
        "name": "Exploitation of Remote Services",
        "tactic": "lateral-movement",
        "keywords": [
            "lateral movement",
            "worm",
            "smb exploit",
            "eternalblue",
            "rpc exploit",
        ],
    },
    "T1041": {
        "name": "Exfiltration Over C2 Channel",
        "tactic": "exfiltration",
        "keywords": [
            "data exfiltration",
            "data theft",
            "covert channel",
            "c2 exfiltration",
        ],
    },
    "T1486": {
        "name": "Data Encrypted for Impact",
        "tactic": "impact",
        "keywords": [
            "ransomware",
            "crypto-locker",
            "extortion",
            "file encryption malware",
        ],
    },
    "T1498": {
        "name": "Network Denial of Service",
        "tactic": "impact",
        "keywords": [
            "dos",
            "ddos",
            "denial of service",
            "amplification attack",
            "flooding",
        ],
    },
    "T1565": {
        "name": "Data Manipulation",
        "tactic": "impact",
        "keywords": [
            "poisoning",
            "data manipulation",
            "model poisoning",
            "adversarial attack",
        ],
    },
}


def _extract_snippet(text: str, term: str, max_len: int = 120) -> str:
    """Extracts a short contextual snippet around matched term."""
    idx = text.lower().find(term.lower())
    if idx == -1:
        clean = " ".join(text.split())
        return clean[:max_len]
    start = max(0, idx - 30)
    end = min(len(text), idx + len(term) + 60)
    raw = text[start:end]
    return " ".join(raw.split())[:max_len]


def _compute_text_hash(title: str, text: str) -> str:
    """Computes first 16 chars of SHA-256 hash over title and text."""
    combined = f"{title}\n{text}".encode("utf-8")
    return hashlib.sha256(combined).hexdigest()[:16]


def _determine_confidence_tier(score: float) -> str:
    """Classifies numerical score into confidence tier string."""
    if score >= 0.8:
        return "HIGH"
    if score >= 0.5:
        return "MEDIUM"
    return "LOW"


def _determine_mechanism(rule_id: Optional[str]) -> str:
    """Maps primary rule ID to inference mechanism identifier."""
    if rule_id == "RULE-EDGE-PAPER-TECH-REGEX-01":
        return "regex_direct_id"
    if rule_id == "RULE-EDGE-PAPER-TECH-TITLE-02":
        return "title_exact_keyword"
    if rule_id == "RULE-EDGE-PAPER-TECH-KEYWORD-03":
        return "title_keyword"
    if rule_id == "RULE-EDGE-PAPER-TECH-ABSTRACT-04":
        return "abstract_semantic_scoring"
    return "lexical"


def _select_primary_rule(applied_rules: List[str]) -> Optional[str]:
    """Selects primary rule by predefined priority hierarchy."""
    priority_order = [
        "RULE-EDGE-PAPER-TECH-REGEX-01",
        "RULE-EDGE-PAPER-TECH-TITLE-02",
        "RULE-EDGE-PAPER-TECH-KEYWORD-03",
        "RULE-EDGE-PAPER-TECH-ABSTRACT-04",
        "RULE-EDGE-FOCUS-OFFENSIVE-01",
    ]
    for rule_id in priority_order:
        if rule_id in applied_rules:
            return rule_id
    return applied_rules[0] if applied_rules else None


@dataclass(frozen=True)
class InferenceEvidence:
    """Audit evidence for an applied rule."""

    rule_id: str
    rule_name: str
    rule_category: str  # pattern, lexical, contextual, semantic_threshold
    matched_terms: List[str]
    target_field: str  # title, abstract, combined
    score_contribution: float
    snippet: str = ""

    def to_dict(self) -> Dict[str, Any]:
        """Serializes evidence to dict."""
        return {
            "rule_id": self.rule_id,
            "rule_name": self.rule_name,
            "rule_category": self.rule_category,
            "matched_terms": self.matched_terms,
            "target_field": self.target_field,
            "score_contribution": round(self.score_contribution, 4),
            "snippet": self.snippet,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> InferenceEvidence:
        """Constructs evidence from dictionary."""
        return cls(
            rule_id=str(data.get("rule_id", "")),
            rule_name=str(data.get("rule_name", "")),
            rule_category=str(data.get("rule_category", "")),
            matched_terms=list(data.get("matched_terms", [])),
            target_field=str(data.get("target_field", "combined")),
            score_contribution=float(data.get("score_contribution", 0.0)),
            snippet=str(data.get("snippet", "")),
        )


@dataclass
class _TechCandidate:
    """Internal candidate representation with matched keywords, rules, and evidences."""

    score: float
    matched_keywords: List[str] = field(default_factory=list)
    applied_rules: List[str] = field(default_factory=list)
    primary_rule_id: Optional[str] = None
    inference_mechanism: str = "lexical"
    evidences: List[InferenceEvidence] = field(default_factory=list)


@dataclass(frozen=True)
class InferredTechnique:
    """Represents a technique inferred from text context with audit metadata."""

    technique_id: str
    technique_name: str
    tactic: str
    confidence: float
    matched_keywords: List[str] = field(default_factory=list)
    research_focus: str = "analysis"  # offensive, defensive, analysis
    applied_rules: List[str] = field(default_factory=list)
    primary_rule_id: Optional[str] = None
    inference_mechanism: str = "lexical"
    evidences: List[InferenceEvidence] = field(default_factory=list)
    confidence_tier: str = "LOW"
    source_text_hash: str = ""
    evidence_quote: str = ""

    def to_dict(self) -> Dict[str, Any]:
        """Serializes inference result to dict."""
        return {
            "technique_id": self.technique_id,
            "technique_name": self.technique_name,
            "tactic": self.tactic,
            "confidence": round(self.confidence, 4),
            "matched_keywords": self.matched_keywords,
            "research_focus": self.research_focus,
            "applied_rules": self.applied_rules,
            "primary_rule_id": self.primary_rule_id,
            "inference_mechanism": self.inference_mechanism,
            "evidences": [e.to_dict() for e in self.evidences],
            "confidence_tier": self.confidence_tier,
            "source_text_hash": self.source_text_hash,
            "evidence_quote": self.evidence_quote,
        }


class TechniqueInferenceEngine:
    """Infers MITRE ATT&CK Techniques using vocabulary matching and heuristics."""

    def __init__(
        self,
        custom_catalog: Optional[Dict[str, Dict[str, Any]]] = None,
        min_confidence: float = 0.4,
        rule_registry: Optional[EdgeInferenceRuleRegistry] = None,
    ) -> None:
        self.catalog = dict(BUILTIN_TECHNIQUE_CATALOG)
        if custom_catalog:
            self.catalog.update(custom_catalog)
        self.min_confidence = min_confidence
        self.rule_registry = rule_registry or EdgeInferenceRuleRegistry()

    def infer(
        self,
        title: str,
        text: str,
        paper_id: Optional[str] = None,
    ) -> List[InferredTechnique]:
        """
        Infers techniques from paper title and abstract/text.
        Returns ranked list of InferredTechnique instances above min_confidence.
        """
        combined_text = f"{title}\n{text}"
        research_focus = self._classify_research_focus(combined_text.lower())
        text_hash = _compute_text_hash(title, text)

        # 1. Direct Regex ID detection
        direct_matches = self._find_direct_technique_ids(title, text)

        # 2. Vocabulary & keyword score map
        candidate_map = self._evaluate_catalog_scores(title, combined_text)

        # Merge direct matches into score map with max confidence
        for tech_id in direct_matches:
            self._apply_direct_match(candidate_map, tech_id, combined_text)

        # Build InferredTechnique results
        results = self._build_inferred_results(candidate_map, research_focus, text_hash)
        return sorted(results, key=lambda x: x.confidence, reverse=True)

    @staticmethod
    def _count_keywords(text: str, keywords: Set[str]) -> int:
        """Counts occurrences of keywords in text."""
        count = 0
        for kw in keywords:
            if kw in text:
                count += 1
        return count

    @staticmethod
    def _is_dominant(count_a: int, count_b: int) -> bool:
        """Checks if count_a is significantly higher than count_b."""
        return count_a > count_b and count_a >= 2

    @classmethod
    def _classify_research_focus(cls, text: str) -> str:
        """Determines if the research is offensive, defensive, or general analysis."""
        off_count = cls._count_keywords(text, OFFENSIVE_KEYWORDS)
        def_count = cls._count_keywords(text, DEFENSIVE_KEYWORDS)

        if cls._is_dominant(off_count, def_count):
            return "offensive"
        if cls._is_dominant(def_count, off_count):
            return "defensive"
        return "analysis"

    @staticmethod
    def _find_direct_technique_ids(title: str, text: str) -> Set[str]:
        """Finds explicit technique IDs (e.g. T1190) via regex."""
        matches = set(TECHNIQUE_ID_REGEX.findall(title))
        matches.update(TECHNIQUE_ID_REGEX.findall(text))
        return {m.upper() for m in matches}

    def _evaluate_catalog_scores(
        self,
        title: str,
        combined_text: str,
    ) -> Dict[str, _TechCandidate]:
        """Computes keyword scores for each technique in the catalog."""
        candidates: Dict[str, _TechCandidate] = {}
        for tech_id, meta in self.catalog.items():
            cand = self._score_single_technique(title, combined_text, meta)
            if cand is not None:
                candidates[tech_id] = cand
        return candidates

    @staticmethod
    def _score_name(
        name: str,
        title: str,
        combined_text: str,
    ) -> Tuple[float, List[str], List[str], List[InferenceEvidence]]:
        """Scores technique name against text."""
        name_lower = name.lower()
        if not name_lower:
            return 0.0, [], [], []
        if name_lower in title.lower():
            rule_id = "RULE-EDGE-PAPER-TECH-TITLE-02"
            ev = InferenceEvidence(
                rule_id=rule_id,
                rule_name="Title Technique Name Affinity",
                rule_category="lexical",
                matched_terms=[name_lower],
                target_field="title",
                score_contribution=0.8,
                snippet=_extract_snippet(title, name_lower),
            )
            return 0.8, [name_lower], [rule_id], [ev]
        if name_lower in combined_text.lower():
            rule_id = "RULE-EDGE-PAPER-TECH-ABSTRACT-04"
            ev = InferenceEvidence(
                rule_id=rule_id,
                rule_name="Abstract Lexical Scoring",
                rule_category="semantic_threshold",
                matched_terms=[name_lower],
                target_field="abstract",
                score_contribution=0.4,
                snippet=_extract_snippet(combined_text, name_lower),
            )
            return 0.4, [name_lower], [rule_id], [ev]
        return 0.0, [], [], []

    @staticmethod
    def _score_single_keyword(
        kw: str,
        title: str,
        combined_text: str,
    ) -> Tuple[float, List[str], List[str], List[InferenceEvidence]]:
        """Scores a single keyword against title and combined text."""
        kw_lower = kw.lower()
        if kw_lower in title.lower():
            rule_id = "RULE-EDGE-PAPER-TECH-KEYWORD-03"
            ev = InferenceEvidence(
                rule_id=rule_id,
                rule_name="Title Important Keyphrase Match",
                rule_category="lexical",
                matched_terms=[kw],
                target_field="title",
                score_contribution=0.5,
                snippet=_extract_snippet(title, kw_lower),
            )
            return 0.5, [kw], [rule_id], [ev]
        if kw_lower in combined_text.lower():
            rule_id = "RULE-EDGE-PAPER-TECH-ABSTRACT-04"
            ev = InferenceEvidence(
                rule_id=rule_id,
                rule_name="Abstract Lexical Scoring",
                rule_category="semantic_threshold",
                matched_terms=[kw],
                target_field="abstract",
                score_contribution=0.25,
                snippet=_extract_snippet(combined_text, kw_lower),
            )
            return 0.25, [kw], [rule_id], [ev]
        return 0.0, [], [], []

    @classmethod
    def _score_keywords(
        cls,
        keywords: List[str],
        title: str,
        combined_text: str,
    ) -> Tuple[float, List[str], List[str], List[InferenceEvidence]]:
        """Scores technique keywords against text."""
        score = 0.0
        matched: List[str] = []
        rules: List[str] = []
        evidences: List[InferenceEvidence] = []
        for kw in keywords:
            s, k, r, ev = cls._score_single_keyword(kw, title, combined_text)
            score += s
            matched.extend(k)
            rules.extend(r)
            evidences.extend(ev)
        return score, matched, rules, evidences

    @classmethod
    def _score_single_technique(
        cls,
        title: str,
        combined_text: str,
        meta: Dict[str, Any],
    ) -> Optional[_TechCandidate]:
        """Scores a single technique against title and combined text."""
        name = str(meta.get("name", ""))
        keywords = list(meta.get("keywords", []))

        name_score, name_kws, name_rules, name_evs = cls._score_name(
            name, title, combined_text
        )
        kw_score, kw_kws, kw_rules, kw_evs = cls._score_keywords(
            keywords, title, combined_text
        )

        total_score = min(name_score + kw_score, 1.0)
        if total_score <= 0.0:
            return None

        all_matched = list(dict.fromkeys(name_kws + kw_kws))
        all_rules = list(dict.fromkeys(name_rules + kw_rules))
        all_evidences = name_evs + kw_evs
        primary = _select_primary_rule(all_rules)
        mechanism = _determine_mechanism(primary)

        return _TechCandidate(
            score=total_score,
            matched_keywords=all_matched,
            applied_rules=all_rules,
            primary_rule_id=primary,
            inference_mechanism=mechanism,
            evidences=all_evidences,
        )

    @staticmethod
    def _apply_direct_match(
        candidate_map: Dict[str, _TechCandidate],
        tech_id: str,
        combined_text: str,
    ) -> None:
        """Applies maximum confidence for directly mentioned technique ID."""
        direct_rule = "RULE-EDGE-PAPER-TECH-REGEX-01"
        direct_ev = InferenceEvidence(
            rule_id=direct_rule,
            rule_name="Direct Technique ID Match",
            rule_category="pattern",
            matched_terms=[tech_id],
            target_field="combined",
            score_contribution=1.0,
            snippet=_extract_snippet(combined_text, tech_id),
        )
        cand = candidate_map.get(tech_id)
        if cand is None:
            candidate_map[tech_id] = _TechCandidate(
                score=1.0,
                matched_keywords=[tech_id],
                applied_rules=[direct_rule],
                primary_rule_id=direct_rule,
                inference_mechanism="regex_direct_id",
                evidences=[direct_ev],
            )
            return
        cand.score = 1.0
        if tech_id not in cand.matched_keywords:
            cand.matched_keywords.append(tech_id)
        if direct_rule not in cand.applied_rules:
            cand.applied_rules.insert(0, direct_rule)
        cand.primary_rule_id = direct_rule
        cand.inference_mechanism = "regex_direct_id"
        cand.evidences.insert(0, direct_ev)

    def _create_inferred_technique(
        self,
        tech_id: str,
        cand: _TechCandidate,
        research_focus: str,
        text_hash: str,
    ) -> InferredTechnique:
        """Constructs a single InferredTechnique instance."""
        meta = self.catalog.get(tech_id, {})
        rules = list(dict.fromkeys(cand.applied_rules))
        evidences = list(cand.evidences)
        if research_focus == "offensive" and cand.score >= self.min_confidence:
            off_rule = "RULE-EDGE-FOCUS-OFFENSIVE-01"
            rules.append(off_rule)
            evidences.append(
                InferenceEvidence(
                    rule_id=off_rule,
                    rule_name="Offensive Context Modifier",
                    rule_category="context_ratio",
                    matched_terms=[research_focus],
                    target_field="combined",
                    score_contribution=0.0,
                    snippet="Research focus classified as offensive",
                )
            )
        primary = cand.primary_rule_id or _select_primary_rule(rules)
        tier = _determine_confidence_tier(cand.score)
        quote = evidences[0].snippet if evidences else ""

        return InferredTechnique(
            technique_id=tech_id,
            technique_name=str(meta.get("name", f"Technique {tech_id}")),
            tactic=str(meta.get("tactic", "unknown")),
            confidence=cand.score,
            matched_keywords=cand.matched_keywords,
            research_focus=research_focus,
            applied_rules=rules,
            primary_rule_id=primary,
            inference_mechanism=cand.inference_mechanism,
            evidences=evidences,
            confidence_tier=tier,
            source_text_hash=text_hash,
            evidence_quote=quote,
        )

    def _build_inferred_results(
        self,
        candidate_map: Dict[str, _TechCandidate],
        research_focus: str,
        text_hash: str,
    ) -> List[InferredTechnique]:
        """Builds InferredTechnique objects filtered by min_confidence."""
        results: List[InferredTechnique] = []
        for tech_id, cand in candidate_map.items():
            if cand.score < self.min_confidence:
                continue
            item = self._create_inferred_technique(
                tech_id, cand, research_focus, text_hash
            )
            results.append(item)
        return results
