#!/usr/bin/env python3
"""
STRIDE Threat Modeling Taxonomy & Category Extraction Engine.
Classifies threats according to Microsoft STRIDE model (Spoofing, Tampering, Repudiation,
Information Disclosure, Denial of Service, Elevation of Privilege).
"""

from typing import Any, Dict, List

STRIDE_CATEGORIES_MAP: Dict[str, Dict[str, Any]] = {
    "Spoofing": {
        "description": "Impersonating an identity, user, or device",
        "security_property": "Authentication",
        "keywords": ["impersonation", "spoofing", "identity theft", "credential stuffing", "forgery"],
    },
    "Tampering": {
        "description": "Modifying data in transit, in memory, or in storage",
        "security_property": "Integrity",
        "keywords": ["tampering", "poisoning", "data corruption", "memory corruption", "backdoor", "code modification"],
    },
    "Repudiation": {
        "description": "Denying having performed an action without accountability",
        "security_property": "Non-Repudiation",
        "keywords": ["provenance", "repudiation", "audit evasion", "log tampering", "untraceable"],
    },
    "Information Disclosure": {
        "description": "Exposing information to unauthorized actors",
        "security_property": "Confidentiality",
        "keywords": ["privacy leakage", "information leakage", "relational privacy", "side channel", "exfiltration"],
    },
    "Denial of Service": {
        "description": "Degrading or denying service to legitimate users",
        "security_property": "Availability",
        "keywords": ["dos", "ddos", "delay attack", "resource exhaustion", "amplification"],
    },
    "Elevation of Privilege": {
        "description": "Gaining unauthorized permissions or capabilities",
        "security_property": "Authorization",
        "keywords": ["privilege escalation", "bypass", "exploit", "sandbox escape", "rooting"],
    },
}


def extract_stride_categories(text: str) -> List[str]:
    """Extracts matching STRIDE categories from given text."""
    if not text:
        return []

    lower_text = text.lower()
    found: List[str] = []
    for cat, meta in STRIDE_CATEGORIES_MAP.items():
        kws = meta.get("keywords", [])
        if any(kw in lower_text for kw in kws):
            found.append(cat)

    return sorted(list(set(found)))
