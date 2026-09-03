#!/usr/bin/env python3
"""
Gold Standard Evaluation Dataset and Benchmarks (DSN-14).
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
        relevant_doc_ids=["2504.11984", "2505.19301", "2508.12259"],
        graded_relevance={"2504.11984": 3.0, "2505.19301": 3.0, "2508.12259": 2.0},
        description="Core zero trust authorization, policy enforcement points, and identity-aware proxies.",
    ),
    EvaluationQuery(
        query_id="Q02",
        query_text="large language model prompt injection jailbreak",
        category="ai-security",
        relevant_doc_ids=["2504.11168", "2505.06493", "2606.20717"],
        graded_relevance={"2504.11168": 3.0, "2505.06493": 3.0, "2606.20717": 2.0},
        description="Adversarial prompt injection, system prompt leakage, and alignment bypass attacks on LLMs.",
    ),
    EvaluationQuery(
        query_id="Q03",
        query_text="post-quantum cryptography lattice based kyber dilithium",
        category="cryptography",
        relevant_doc_ids=["iacr-2026-1098", "2505.08791", "2508.10023"],
        graded_relevance={"iacr-2026-1098": 3.0, "2505.08791": 3.0, "2508.10023": 2.0},
        description="NIST PQC standardized algorithms (ML-KEM, ML-DSA) and lattice cryptanalysis.",
    ),
    EvaluationQuery(
        query_id="Q04",
        query_text="microarchitectural side-channel transient execution spectre meltdown",
        category="hardware-security",
        relevant_doc_ids=["2511.17726", "2510.18612", "2510.13111"],
        graded_relevance={"2511.17726": 3.0, "2510.18612": 3.0, "2510.13111": 2.0},
        description="Cache timing attacks, speculative execution vulnerabilities, and branch prediction side-channels.",
    ),
    EvaluationQuery(
        query_id="Q05",
        query_text="web application firewall sql injection cross site scripting xss",
        category="web-security",
        relevant_doc_ids=["2506.17245", "2509.10920", "2604.19526"],
        graded_relevance={"2506.17245": 3.0, "2509.10920": 3.0, "2604.19526": 2.0},
        description="OWASP Top 10 vulnerabilities, automated payload obfuscation, and WAF evasion mitigations.",
    ),
]
