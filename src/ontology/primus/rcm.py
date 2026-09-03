#!/usr/bin/env python3
"""
PRIMUS CTI-RCM (Root Cause Mapping).
Infers CWE vulnerability classifications from natural language descriptions,
academic abstracts, and explicit vulnerability references.
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

from .provenance import ProvenanceRecord, assign_provenance

EXPLICIT_CWE_RE = re.compile(r"\b(CWE[-_](\d{1,5}))\b", re.IGNORECASE)

ROOT_CAUSE_PATTERNS: List[Tuple[str, str, re.Pattern[str], float]] = [
    (
        "CWE-787",
        "Out-of-bounds Write",
        re.compile(
            r"(?i)\b(out[- ]of[- ]bounds write|heap overflow|stack overflow|buffer overflow)\b"
        ),
        0.82,
    ),
    (
        "CWE-125",
        "Out-of-bounds Read",
        re.compile(
            r"(?i)\b(out[- ]of[- ]bounds read|over[- ]read|buffer over[- ]read)\b"
        ),
        0.80,
    ),
    (
        "CWE-416",
        "Use After Free",
        re.compile(r"(?i)\b(use[- ]after[- ]free|uaf vulnerability)\b"),
        0.88,
    ),
    (
        "CWE-415",
        "Double Free",
        re.compile(r"(?i)\b(double[- ]free|double free vulnerability)\b"),
        0.88,
    ),
    (
        "CWE-362",
        "Race Condition",
        re.compile(
            r"(?i)\b(race condition|time[- ]of[- ]check time[- ]of[- ]use|toctou)\b"
        ),
        0.85,
    ),
    (
        "CWE-89",
        "SQL Injection",
        re.compile(r"(?i)\b(sql injection|sqli|blind sql)\b"),
        0.90,
    ),
    (
        "CWE-79",
        "Cross-site Scripting",
        re.compile(r"(?i)\b(cross[- ]site scripting|xss|dom[- ]based xss)\b"),
        0.88,
    ),
    (
        "CWE-78",
        "OS Command Injection",
        re.compile(
            r"(?i)\b(command injection|shell injection|remote command execution)\b"
        ),
        0.86,
    ),
    (
        "CWE-22",
        "Path Traversal",
        re.compile(r"(?i)\b(path traversal|directory traversal|directory climbing)\b"),
        0.86,
    ),
    (
        "CWE-502",
        "Deserialization of Untrusted Data",
        re.compile(r"(?i)\b(insecure deserialization|pickle load|unsafe unpickling)\b"),
        0.87,
    ),
    (
        "CWE-918",
        "Server-Side Request Forgery",
        re.compile(r"(?i)\b(server[- ]side request forgery|ssrf)\b"),
        0.90,
    ),
    (
        "CWE-287",
        "Improper Authentication",
        re.compile(
            r"(?i)\b(authentication bypass|broken authentication|spoofed token)\b"
        ),
        0.80,
    ),
    (
        "CWE-798",
        "Use of Hard-coded Credentials",
        re.compile(r"(?i)\b(hardcoded credential|hardcoded key|embedded password)\b"),
        0.85,
    ),
    (
        "CWE-1321",
        "Prototype Pollution",
        re.compile(r"(?i)\b(prototype pollution|proto pollution)\b"),
        0.89,
    ),
    (
        "CWE-385",
        "Covert Timing Channel",
        re.compile(
            r"(?i)\b(side[- ]channel attack|timing attack|microarchitectural attack|cache attack)\b"
        ),
        0.82,
    ),
    (
        "CWE-1426",
        "Improper Validation of Generative AI Input",
        re.compile(
            r"(?i)\b(prompt injection|jailbreak prompt|adversarial jailbreak|llm backdoor)\b"
        ),
        0.85,
    ),
]


class RootCauseMapper:
    """CTI-RCM Root Cause Mapper engine."""

    @classmethod
    def _extract_explicit_cwes(
        cls,
        text: str,
        seen_cwes: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        for match in EXPLICIT_CWE_RE.finditer(text):
            num = match.group(2)
            canonical = f"CWE-{int(num)}"
            snippet = text[
                max(0, match.start() - 30) : min(len(text), match.end() + 30)
            ]
            rec = assign_provenance(
                mapped_id=canonical,
                category="CWE",
                confidence=0.98,
                evidence_snippet=snippet,
                is_explicit=True,
                source_rule="CTI-RCM-Explicit",
            )
            if rec and canonical not in seen_cwes:
                seen_cwes[canonical] = rec.confidence
                results.append(rec)

    @classmethod
    def _match_single_cwe(
        cls,
        text: str,
        cwe_id: str,
        desc: str,
        pattern: re.Pattern[str],
        base_conf: float,
    ) -> Optional[ProvenanceRecord]:
        m = pattern.search(text)
        if not m:
            return None
        snippet = text[max(0, m.start() - 30) : min(len(text), m.end() + 30)]
        return assign_provenance(
            mapped_id=cwe_id,
            category="CWE",
            confidence=base_conf,
            evidence_snippet=snippet,
            is_explicit=False,
            source_rule=f"CTI-RCM-{desc.replace(' ', '')}",
        )

    @classmethod
    def _infer_pattern_cwes(
        cls,
        text: str,
        seen_cwes: Dict[str, float],
        results: List[ProvenanceRecord],
    ) -> None:
        for cwe_id, desc, pattern, base_conf in ROOT_CAUSE_PATTERNS:
            if cwe_id not in seen_cwes:
                rec = cls._match_single_cwe(text, cwe_id, desc, pattern, base_conf)
                if rec:
                    seen_cwes[cwe_id] = rec.confidence
                    results.append(rec)

    @classmethod
    def map_root_causes(cls, text: str) -> List[ProvenanceRecord]:
        """Extracts explicit and inferred CWE vulnerability IDs with provenance tiering."""
        results: List[ProvenanceRecord] = []
        seen_cwes: Dict[str, float] = {}
        cls._extract_explicit_cwes(text, seen_cwes, results)
        cls._infer_pattern_cwes(text, seen_cwes, results)
        return results
