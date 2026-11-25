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
from ontology.rule_schema import EdgeInferenceRule

# Regex pattern for direct ATT&CK Technique ID detection
TECHNIQUE_ID_REGEX = re.compile(r"\b(T\d{4}(?:\.\d{3})?)\b", re.IGNORECASE)

# Canonical EIROM rule identifiers used by TechniqueInferenceEngine
RULE_DIRECT_REGEX = "RULE-EDGE-PAPER-TECH-REGEX-01"
RULE_TITLE_NAME = "RULE-EDGE-PAPER-TECH-TITLE-02"
RULE_TITLE_KEYWORD = "RULE-EDGE-PAPER-TECH-KEYWORD-03"
RULE_ABSTRACT_SCORING = "RULE-EDGE-PAPER-TECH-ABSTRACT-04"
RULE_FOCUS_OFFENSIVE = "RULE-EDGE-FOCUS-OFFENSIVE-01"

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
        RULE_DIRECT_REGEX,
        RULE_TITLE_NAME,
        RULE_TITLE_KEYWORD,
        RULE_ABSTRACT_SCORING,
        RULE_FOCUS_OFFENSIVE,
    ]
    for rule_id in priority_order:
        if rule_id in applied_rules:
            return rule_id
    return applied_rules[0] if applied_rules else None


def _spec_float(spec: Dict[str, Any], key: str, default: float) -> float:
    """Safely extracts float parameter from condition_spec."""
    raw = spec.get(key)
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return float(raw)
    return default


def _spec_int(spec: Dict[str, Any], key: str, default: int) -> int:
    """Safely extracts positive integer parameter from condition_spec."""
    raw = spec.get(key)
    if isinstance(raw, int) and not isinstance(raw, bool):
        return raw
    return default


def _compile_rule_regex(rule: EdgeInferenceRule) -> re.Pattern[str]:
    """Compiles regex pattern from a validated EdgeInferenceRule."""
    pattern = str(rule.condition_spec.get("pattern", ""))
    flags = 0 if rule.evidence_spec.case_sensitive else re.IGNORECASE
    return re.compile(pattern, flags)


def _extract_regex_matches(pattern: re.Pattern[str], text: str) -> Set[str]:
    """Extracts upper-cased matched technique identifiers from text."""
    return {match.group(0).upper() for match in pattern.finditer(text)}


def _build_rule_evidence(
    rule: EdgeInferenceRule,
    matched_terms: List[str],
    score: float,
    text: str,
    term: str,
    category_override: Optional[str] = None,
) -> InferenceEvidence:
    """Constructs audit evidence using metadata from an active EIROM rule."""
    category = category_override or rule.condition_type.value
    snippet = _extract_snippet(
        text, term, max_len=rule.evidence_spec.max_snippet_length
    )
    return InferenceEvidence(
        rule_id=rule.rule_id,
        rule_name=rule.name,
        rule_category=category,
        matched_terms=matched_terms,
        target_field=rule.evidence_spec.target_field,
        score_contribution=score,
        snippet=snippet,
    )


def _merge_direct_candidate(
    candidate_map: Dict[str, _TechCandidate],
    tech_id: str,
    rule_id: str,
    score: float,
    direct_ev: InferenceEvidence,
) -> None:
    """Inserts or promotes a candidate with direct regex match evidence."""
    cand = candidate_map.get(tech_id)
    if cand is None:
        candidate_map[tech_id] = _TechCandidate(
            score=score,
            matched_keywords=[tech_id],
            applied_rules=[rule_id],
            primary_rule_id=rule_id,
            inference_mechanism="regex_direct_id",
            evidences=[direct_ev],
        )
        return
    cand.score = max(cand.score, score)
    if tech_id not in cand.matched_keywords:
        cand.matched_keywords.append(tech_id)
    if rule_id not in cand.applied_rules:
        cand.applied_rules.insert(0, rule_id)
    cand.primary_rule_id = rule_id
    cand.inference_mechanism = "regex_direct_id"
    cand.evidences.insert(0, direct_ev)


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
    """Infers MITRE ATT&CK Techniques using vocabulary matching and EIROM rules."""

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
        self._regex_cache_key: Optional[Tuple[str, bool]] = None
        self._compiled_direct_regex: Optional[re.Pattern[str]] = None

    def _get_active_rule(self, rule_id: str) -> Optional[EdgeInferenceRule]:
        """Returns registered rule only when present and active."""
        rule = self.rule_registry.get_rule(rule_id)
        if rule is None or not rule.is_active:
            return None
        return rule

    def _get_direct_regex(self) -> Optional[Tuple[EdgeInferenceRule, re.Pattern[str]]]:
        """Returns active direct regex rule and its cached compiled pattern."""
        rule = self._get_active_rule(RULE_DIRECT_REGEX)
        if rule is None:
            return None
        pattern_str = str(rule.condition_spec.get("pattern", ""))
        cache_key = (pattern_str, rule.evidence_spec.case_sensitive)
        if self._compiled_direct_regex is None or self._regex_cache_key != cache_key:
            self._compiled_direct_regex = _compile_rule_regex(rule)
            self._regex_cache_key = cache_key
        return rule, self._compiled_direct_regex

    def _get_dominant_factor(self) -> int:
        """Reads dominant threshold factor from active offensive context rule."""
        rule = self._get_active_rule(RULE_FOCUS_OFFENSIVE)
        if rule is None:
            return 2
        return max(1, _spec_int(rule.condition_spec, "dominant_factor", 2))

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

        # 1. Direct Regex ID detection driven by EIROM registry
        direct_matches = self._find_direct_technique_ids(title, text)

        # 2. Vocabulary & keyword score map driven by EIROM registry
        candidate_map = self._evaluate_catalog_scores(title, combined_text)

        # Merge direct matches into score map
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
    def _is_dominant(count_a: int, count_b: int, dominant_factor: int = 2) -> bool:
        """Checks if count_a exceeds count_b and meets minimum threshold."""
        return count_a > count_b and count_a >= dominant_factor

    def _classify_research_focus(self, text: str) -> str:
        """Determines if the research is offensive, defensive, or general analysis."""
        factor = self._get_dominant_factor()
        off_count = self._count_keywords(text, OFFENSIVE_KEYWORDS)
        def_count = self._count_keywords(text, DEFENSIVE_KEYWORDS)

        if self._is_dominant(off_count, def_count, factor):
            return "offensive"
        if self._is_dominant(def_count, off_count, factor):
            return "defensive"
        return "analysis"

    def _find_direct_technique_ids(self, title: str, text: str) -> Set[str]:
        """Finds explicit technique IDs via active EIROM regex rule."""
        active = self._get_direct_regex()
        if active is None:
            return set()
        _, pattern = active
        matches = _extract_regex_matches(pattern, title)
        matches.update(_extract_regex_matches(pattern, text))
        return matches

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

    def _match_title_name(
        self,
        name_lower: str,
        title: str,
    ) -> Optional[Tuple[float, List[str], List[str], List[InferenceEvidence]]]:
        """Applies RULE-EDGE-PAPER-TECH-TITLE-02 when active and matched."""
        if name_lower not in title.lower():
            return None
        rule = self._get_active_rule(RULE_TITLE_NAME)
        if rule is None:
            return None
        score = rule.base_confidence
        ev = _build_rule_evidence(rule, [name_lower], score, title, name_lower)
        return score, [name_lower], [rule.rule_id], [ev]

    def _match_abstract_name(
        self,
        name_lower: str,
        combined_text: str,
    ) -> Optional[Tuple[float, List[str], List[str], List[InferenceEvidence]]]:
        """Applies RULE-EDGE-PAPER-TECH-ABSTRACT-04 to technique name in body."""
        if name_lower not in combined_text.lower():
            return None
        rule = self._get_active_rule(RULE_ABSTRACT_SCORING)
        if rule is None:
            return None
        score = _spec_float(rule.condition_spec, "min_threshold", 0.4)
        ev = _build_rule_evidence(rule, [name_lower], score, combined_text, name_lower)
        return score, [name_lower], [rule.rule_id], [ev]

    def _score_name(
        self,
        name: str,
        title: str,
        combined_text: str,
    ) -> Tuple[float, List[str], List[str], List[InferenceEvidence]]:
        """Scores technique name against text using registered EIROM rules."""
        name_lower = name.lower()
        if not name_lower:
            return 0.0, [], [], []
        title_hit = self._match_title_name(name_lower, title)
        if title_hit is not None:
            return title_hit
        abstract_hit = self._match_abstract_name(name_lower, combined_text)
        if abstract_hit is not None:
            return abstract_hit
        return 0.0, [], [], []

    def _match_title_keyword(
        self,
        kw: str,
        title: str,
    ) -> Optional[Tuple[float, List[str], List[str], List[InferenceEvidence]]]:
        """Applies RULE-EDGE-PAPER-TECH-KEYWORD-03 for a single title keyword."""
        kw_lower = kw.lower()
        if kw_lower not in title.lower():
            return None
        rule = self._get_active_rule(RULE_TITLE_KEYWORD)
        if rule is None:
            return None
        weight = _spec_float(
            rule.condition_spec, "weight_per_keyword", rule.base_confidence
        )
        ev = _build_rule_evidence(rule, [kw], weight, title, kw_lower)
        return weight, [kw], [rule.rule_id], [ev]

    def _match_abstract_keyword(
        self,
        kw: str,
        combined_text: str,
    ) -> Optional[Tuple[float, List[str], List[str], List[InferenceEvidence]]]:
        """Applies RULE-EDGE-PAPER-TECH-ABSTRACT-04 for a single body keyword."""
        kw_lower = kw.lower()
        if kw_lower not in combined_text.lower():
            return None
        rule = self._get_active_rule(RULE_ABSTRACT_SCORING)
        if rule is None:
            return None
        weight = _spec_float(rule.condition_spec, "abstract_weight", 0.25)
        ev = _build_rule_evidence(rule, [kw], weight, combined_text, kw_lower)
        return weight, [kw], [rule.rule_id], [ev]

    def _score_single_keyword(
        self,
        kw: str,
        title: str,
        combined_text: str,
    ) -> Tuple[float, List[str], List[str], List[InferenceEvidence]]:
        """Scores a single keyword against title and combined text."""
        title_hit = self._match_title_keyword(kw, title)
        if title_hit is not None:
            return title_hit
        abstract_hit = self._match_abstract_keyword(kw, combined_text)
        if abstract_hit is not None:
            return abstract_hit
        return 0.0, [], [], []

    def _score_keywords(
        self,
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
            s, k, r, ev = self._score_single_keyword(kw, title, combined_text)
            score += s
            matched.extend(k)
            rules.extend(r)
            evidences.extend(ev)
        return score, matched, rules, evidences

    def _score_single_technique(
        self,
        title: str,
        combined_text: str,
        meta: Dict[str, Any],
    ) -> Optional[_TechCandidate]:
        """Scores a single technique against title and combined text."""
        name = str(meta.get("name", ""))
        keywords = list(meta.get("keywords", []))

        name_score, name_kws, name_rules, name_evs = self._score_name(
            name, title, combined_text
        )
        kw_score, kw_kws, kw_rules, kw_evs = self._score_keywords(
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

    def _apply_direct_match(
        self,
        candidate_map: Dict[str, _TechCandidate],
        tech_id: str,
        combined_text: str,
    ) -> None:
        """Applies confidence from active direct regex rule for explicit technique ID."""
        rule = self._get_active_rule(RULE_DIRECT_REGEX)
        if rule is None:
            return
        direct_ev = _build_rule_evidence(
            rule,
            [tech_id],
            rule.base_confidence,
            combined_text,
            tech_id,
            category_override="pattern",
        )
        _merge_direct_candidate(
            candidate_map,
            tech_id,
            rule.rule_id,
            rule.base_confidence,
            direct_ev,
        )

    def _append_offensive_modifier(
        self,
        research_focus: str,
        score: float,
        rules: List[str],
        evidences: List[InferenceEvidence],
    ) -> None:
        """Appends offensive context modifier rule and evidence when active."""
        if research_focus != "offensive" or score < self.min_confidence:
            return
        rule = self._get_active_rule(RULE_FOCUS_OFFENSIVE)
        if rule is None:
            return
        rules.append(rule.rule_id)
        evidences.append(
            InferenceEvidence(
                rule_id=rule.rule_id,
                rule_name=rule.name,
                rule_category=rule.condition_type.value,
                matched_terms=[research_focus],
                target_field=rule.evidence_spec.target_field,
                score_contribution=0.0,
                snippet="Research focus classified as offensive",
            )
        )

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
        self._append_offensive_modifier(research_focus, cand.score, rules, evidences)
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
