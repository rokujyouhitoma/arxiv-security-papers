#!/usr/bin/env python3
"""
Gold Standard Evaluation Dataset for arXiv Security Papers.
Contains curated queries, category tags, relevant document IDs, and graded relevance scores
(1: relevant, 2: highly relevant, 3: perfect).
"""

from typing import Dict, List, Optional


class EvaluationQuery:
    """Represents a single benchmark query with ground-truth relevance annotations."""

    def __init__(
        self,
        query_id: str,
        query_text: str,
        category: str,
        relevant_doc_ids: List[str],
        graded_relevance: Optional[Dict[str, float]] = None,
        description: str = "",
    ) -> None:
        self.query_id = query_id
        self.query_text = query_text
        self.category = category
        self.relevant_doc_ids = relevant_doc_ids
        self.graded_relevance = graded_relevance or {
            doc_id: 1.0 for doc_id in relevant_doc_ids
        }
        self.description = description


DEFAULT_SECURITY_GOLD_STANDARD: List[EvaluationQuery] = [
    EvaluationQuery(
        query_id="Q01",
        query_text="zero trust architecture access control",
        category="zero-trust",
        relevant_doc_ids=["2602.0001", "2602.0002", "2602.0003"],
        graded_relevance={"2602.0001": 3.0, "2602.0002": 2.0, "2602.0003": 1.0},
        description="Core zero trust authorization, policy enforcement points, and identity-aware proxies.",
    ),
    EvaluationQuery(
        query_id="Q02",
        query_text="large language model prompt injection jailbreak",
        category="ai-security",
        relevant_doc_ids=["2602.0010", "2602.0011", "2602.0012"],
        graded_relevance={"2602.0010": 3.0, "2602.0011": 2.0, "2602.0012": 2.0},
        description="Adversarial prompt injection, system prompt leakage, and alignment bypass attacks on LLMs.",
    ),
    EvaluationQuery(
        query_id="Q03",
        query_text="post-quantum cryptography lattice based kyber dilithium",
        category="cryptography",
        relevant_doc_ids=["2602.0020", "2602.0021"],
        graded_relevance={"2602.0020": 3.0, "2602.0021": 3.0},
        description="NIST PQC standardized algorithms (ML-KEM, ML-DSA) and lattice cryptanalysis.",
    ),
    EvaluationQuery(
        query_id="Q04",
        query_text="microarchitectural side-channel transient execution spectre meltdown",
        category="hardware-security",
        relevant_doc_ids=["2602.0030", "2602.0031", "2602.0032"],
        graded_relevance={"2602.0030": 3.0, "2602.0031": 2.0, "2602.0032": 1.0},
        description="Cache timing attacks, speculative execution vulnerabilities, and branch prediction side-channels.",
    ),
    EvaluationQuery(
        query_id="Q05",
        query_text="web application firewall sql injection cross site scripting xss",
        category="web-security",
        relevant_doc_ids=["2602.0040", "2602.0041"],
        graded_relevance={"2602.0040": 3.0, "2602.0041": 2.0},
        description="OWASP Top 10 vulnerabilities, automated payload obfuscation, and WAF evasion mitigations.",
    ),
]
