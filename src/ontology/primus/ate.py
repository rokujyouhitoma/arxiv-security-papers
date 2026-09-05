#!/usr/bin/env python3
"""
PRIMUS CTI-ATE (Attack Technique Extraction).
Extracts MITRE ATT&CK Enterprise and ATLAS Technique IDs from natural language
attack descriptions, PoC methods, and explicit identifiers.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from .provenance import ProvenanceRecord, assign_provenance

EXPLICIT_ATTCK_RE = re.compile(r"\b(T\d{4}(?:\.\d{3})?)\b")
EXPLICIT_ATLAS_RE = re.compile(r"\b(AML\.T\d{4}(?:\.\d{3})?)\b")

TECHNIQUE_PATTERNS: List[Tuple[str, str, re.Pattern[str], float]] = [
    (
        "T1059",
        "Command and Scripting Interpreter",
        re.compile(
            r"(?i)\b(command execution|script interpreter|powershell payload|bash script|shell execution)\b"
        ),
        0.85,
    ),
    (
        "T1190",
        "Exploit Public-Facing Application",
        re.compile(
            r"(?i)\b(public[- ]facing application|web application exploit|unauthenticated rce|remote exploitation)\b"
        ),
        0.88,
    ),
    (
        "T1068",
        "Exploitation for Privilege Escalation",
        re.compile(
            r"(?i)\b(privilege escalation|escalate to root|kernel exploit|lpe)\b"
        ),
        0.86,
    ),
    (
        "T1203",
        "Exploitation for Client Execution",
        re.compile(
            r"(?i)\b(client[- ]side exploit|browser exploit|pdf reader vulnerability)\b"
        ),
        0.84,
    ),
    (
        "T1498",
        "Network Denial of Service",
        re.compile(
            r"(?i)\b(denial of service|ddos attack|amplification attack|packet flooding)\b"
        ),
        0.86,
    ),
    (
        "T1003",
        "OS Credential Dumping",
        re.compile(
            r"(?i)\b(credential dumping|memory dumping|lsass dump|extracting password hashes)\b"
        ),
        0.89,
    ),
    (
        "T1574",
        "Hijack Execution Flow",
        re.compile(r"(?i)\b(dll hijacking|library injection|ld_preload hijacking)\b"),
        0.87,
    ),
    (
        "T1566",
        "Phishing",
        re.compile(r"(?i)\b(spearphishing|phishing email|malicious attachment)\b"),
        0.85,
    ),
    (
        "AML.T0015",
        "Evade ML Model",
        re.compile(
            r"(?i)\b(adversarial example|adversarial perturbation|evasion attack against model)\b"
        ),
        0.90,
    ),
    (
        "AML.T0018",
        "Poison Training Data",
        re.compile(
            r"(?i)\b(data poisoning|training data poisoning|backdoor attack on model)\b"
        ),
        0.90,
    ),
    (
        "AML.T0043",
        "Model Inversion",
        re.compile(
            r"(?i)\b(model inversion|membership inference|extracting private training data)\b"
        ),
        0.88,
    ),
    (
        "AML.T0054",
        "LLM Jailbreak",
        re.compile(
            r"(?i)\b(jailbreaking llm|prompt injection attack|jailbreak attack)\b"
        ),
        0.91,
    ),
]


class AttackTechniqueExtractor:
    """CTI-ATE Attack Technique Extractor engine."""

    @classmethod
    def _extract_explicit_matches(
        cls,
        text: str,
        regex: re.Pattern[str],
        category: str,
        rule_name: str,
        seen: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        for match in regex.finditer(text):
            tech_id = match.group(1).upper()
            snippet = text[
                max(0, match.start() - 30) : min(len(text), match.end() + 30)
            ]
            rec = assign_provenance(
                mapped_id=tech_id,
                category=category,
                confidence=0.98,
                evidence_snippet=snippet,
                is_explicit=True,
                source_rule=rule_name,
            )
            if rec and tech_id not in seen:
                seen[tech_id] = rec.confidence
                results.append(rec)

    @classmethod
    def _match_single_pattern(
        cls,
        text: str,
        tech_id: str,
        name: str,
        pattern: re.Pattern[str],
        base_conf: float,
    ) -> Optional[ProvenanceRecord]:
        m = pattern.search(text)
        if not m:
            return None
        snippet = text[max(0, m.start() - 30) : min(len(text), m.end() + 30)]
        cat = "ATLAS" if tech_id.startswith("AML.") else "ATT&CK"
        return assign_provenance(
            mapped_id=tech_id,
            category=cat,
            confidence=base_conf,
            evidence_snippet=snippet,
            is_explicit=False,
            source_rule=f"CTI-ATE-{name.replace(' ', '')}",
        )

    @classmethod
    def _infer_pattern_techniques(
        cls,
        text: str,
        seen: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        for tech_id, name, pattern, base_conf in TECHNIQUE_PATTERNS:
            if tech_id not in seen:
                rec = cls._match_single_pattern(text, tech_id, name, pattern, base_conf)
                if rec:
                    seen[tech_id] = rec.confidence
                    results.append(rec)

    @classmethod
    def _find_keyword_in_meta(
        cls, meta: Dict[str, Any], lower_text: str
    ) -> Optional[Tuple[str, int]]:
        for kw in meta.get("keywords", []):
            if kw and kw in lower_text:
                return kw, lower_text.find(kw)
        return None

    @classmethod
    def _create_cti_provenance(
        cls, text: str, tech_id: str, kw: str, pos: int
    ) -> Optional[ProvenanceRecord]:
        snippet = text[max(0, pos - 30) : min(len(text), pos + len(kw) + 30)]
        return assign_provenance(
            mapped_id=tech_id,
            category="ATT&CK",
            confidence=0.82,
            evidence_snippet=snippet,
            is_explicit=False,
            source_rule="CTI-ATE-CatalogKeyword",
        )

    @classmethod
    def _match_cti_tech(
        cls,
        text: str,
        lower_text: str,
        tech_id: str,
        meta: Dict[str, Any],
        seen: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        if tech_id in seen:
            return
        match = cls._find_keyword_in_meta(meta, lower_text)
        if not match:
            return
        rec = cls._create_cti_provenance(text, tech_id, match[0], match[1])
        if rec:
            seen[tech_id] = rec.confidence
            results.append(rec)

    @classmethod
    def _infer_cti_registry_techniques(
        cls,
        text: str,
        seen: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        try:
            from security.cti.registry import MITRECTIRegistry

            registry = MITRECTIRegistry.get_instance()
            lower_text = text.lower()
            for tech_id, meta in registry.get_all_techniques().items():
                cls._match_cti_tech(text, lower_text, tech_id, meta, seen, results)
        except Exception:
            pass

    @classmethod
    def extract_techniques(cls, text: str) -> List[ProvenanceRecord]:
        """Extracts MITRE ATT&CK and ATLAS technique IDs with Gold/Silver provenance."""
        results: List[ProvenanceRecord] = []
        seen: Dict[str, float] = {}

        cls._extract_explicit_matches(
            text, EXPLICIT_ATTCK_RE, "ATT&CK", "CTI-ATE-Explicit-ATTCK", seen, results
        )
        cls._extract_explicit_matches(
            text, EXPLICIT_ATLAS_RE, "ATLAS", "CTI-ATE-Explicit-ATLAS", seen, results
        )
        cls._infer_pattern_techniques(text, seen, results)
        cls._infer_cti_registry_techniques(text, seen, results)
        return results
