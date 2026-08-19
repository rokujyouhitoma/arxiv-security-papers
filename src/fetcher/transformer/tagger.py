#!/usr/bin/env python3
"""
Security Domain Classifier & Threat Model Tagger Module
Extracts domain tags, MITRE ATT&CK technique IDs, and STRIDE categories from paper metadata.
"""

from typing import Any, Dict, List

DOMAIN_KEYWORDS: List[tuple[str, List[str]]] = [
    (
        "AI/ML Security",
        [
            "llm",
            "prompt injection",
            "agent",
            "mllm",
            "rag",
            "adversarial attack",
            "machine learning",
        ],
    ),
    (
        "Cryptography",
        [
            "cryptography",
            "encryption",
            "zero-knowledge",
            "lattice",
            "signature",
            "rsa",
            "ecc",
        ],
    ),
    (
        "Network Security",
        ["network", "quic", "darknet", "traffic", "routing", "ddos", "dns", "firewall"],
    ),
    (
        "Software Security",
        [
            "malware",
            "fuzzing",
            "vulnerability",
            "bytecode",
            "smart contract",
            "exploit",
            "binary",
        ],
    ),
    (
        "Privacy & Provenance",
        [
            "privacy",
            "anonymity",
            "differential privacy",
            "watermark",
            "provenance",
            "leakage",
        ],
    ),
    (
        "IoT & Hardware Security",
        [
            "iot",
            "vehicle",
            "autonomous",
            "smart grid",
            "embedded",
            "firmware",
            "arm cca",
        ],
    ),
]


def classify_domain(paper: Dict[str, Any]) -> str:
    """Classifies paper into primary security domain."""
    text = (
        f"{paper.get('title', '')} {paper.get('summary', '')} {' '.join(paper.get('categories', []))}"
    ).lower()

    for domain, keywords in DOMAIN_KEYWORDS:
        if any(k in text for k in keywords):
            return domain

    return "General Cyber Security"


def determine_security_tags(paper: Dict[str, Any]) -> List[str]:
    """Extracts granular security tags based on categories and text keywords."""
    tags = list(paper.get("categories", ["cs.CR"]))
    domain = classify_domain(paper)
    tags.append(domain)

    text = f"{paper.get('title', '')} {paper.get('summary', '')}".lower()
    tag_rules = [
        (["llm", "agent", "prompt"], "llm-security"),
        (["malware", "virus", "trojan"], "malware-analysis"),
        (["fuzzing", "fuzzer", "crash"], "fuzzing"),
        (["privacy", "anonymity"], "privacy-preservation"),
        (["network", "protocol", "quic"], "network-protocol"),
        (["hardware", "arm", "enclave"], "trusted-execution"),
        (["blockchain", "smart contract"], "blockchain-forensics"),
        (["provenance", "watermark"], "data-provenance"),
    ]

    for keywords, tag in tag_rules:
        if any(k in text for k in keywords):
            tags.append(tag)

    return sorted(list(set(tags)))


def extract_mitre_and_stride(
    paper: Dict[str, Any], text: str = ""
) -> Dict[str, List[str]]:
    """Extracts MITRE ATT&CK techniques and STRIDE threat categories from text."""
    from security.taxonomy import extract_mitre_techniques, extract_stride_categories

    combined = f"{paper.get('title', '')} {paper.get('summary', '')} {text}"
    return {
        "mitre_attack": extract_mitre_techniques(combined),
        "stride": extract_stride_categories(combined),
    }
