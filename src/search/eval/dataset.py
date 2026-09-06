#!/usr/bin/env python3
"""
Gold Standard Evaluation Dataset and Benchmarks (DSN-14).
Contains curated queries, category tags, relevant document IDs, and graded relevance scores
(1: relevant, 2: highly relevant, 3: perfect).
"""

from typing import Any, Dict, List, Optional, Tuple


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


class BEIRDataset:
    """Represents a standard BEIR-compatible information retrieval benchmark dataset."""

    def __init__(
        self,
        name: str,
        corpus: Dict[str, Dict[str, Any]],
        queries: Dict[str, str],
        qrels: Dict[str, Dict[str, float]],
    ) -> None:
        self.name = name
        self.corpus = corpus
        self.queries = queries
        self.qrels = qrels

    def to_evaluation_queries(self) -> List[EvaluationQuery]:
        """Converts BEIR queries and qrels into EvaluationQuery objects."""
        results: List[EvaluationQuery] = []
        for q_id, q_text in self.queries.items():
            rel_map = self.qrels.get(q_id, {})
            rel_docs = [doc_id for doc_id, score in rel_map.items() if score > 0.0]
            results.append(
                EvaluationQuery(
                    query_id=q_id,
                    query_text=q_text,
                    category="beir-benchmark",
                    relevant_doc_ids=rel_docs,
                    graded_relevance=rel_map,
                    description=f"BEIR Evaluation Query {q_id}",
                )
            )
        return results


def _build_cti_corpus(num_docs: int) -> Dict[str, Dict[str, Any]]:
    import hashlib

    themes = [
        (
            "zero-trust",
            "Zero-Trust Architecture and Micro-segmentation",
            "Identity-aware proxies, continuous authentication, and mutual TLS policy "
            "enforcement across zero-trust networks.",
        ),
        (
            "llm-security",
            "Adversarial Prompt Injection and Jailbreaking in Large Language Models",
            "System prompt exfiltration, recursive prompt hijacking, and safety alignment "
            "guardrail evaluation in multi-agent LLM systems.",
        ),
        (
            "cryptography",
            "Post-Quantum Lattice-based Cryptography and Lattice Reduction",
            "NIST ML-KEM, ML-DSA signature verification, Kyber lattice attacks, and "
            "fault-injection vulnerability mitigations.",
        ),
        (
            "hardware-security",
            "Transient Execution Microarchitectural Attacks and Speculative Cache Side-Channels",
            "Spectre-v2, Meltdown, Branch Target Buffer collision, and hardware-enforced "
            "speculative execution barriers.",
        ),
        (
            "supply-chain",
            "Software Supply Chain Security and Dependency Confusion",
            "Typosquatting in package registries, malicious post-install hooks, and "
            "cryptographic provenance attestation with SLSA.",
        ),
        (
            "malware-evasion",
            "Evasive Ransomware and Memory-Only Living-off-the-Land Binaries",
            "LOLBins, process hollowing, API hooking evasion, and endpoint detection "
            "and response (EDR) bypass techniques.",
        ),
    ]

    corpus: Dict[str, Dict[str, Any]] = {}
    for i in range(num_docs):
        theme_idx = i % len(themes)
        tag, title_base, desc_base = themes[theme_idx]
        doc_id = f"cti-{tag}-{i:04d}"
        seed = int(hashlib.md5(f"{doc_id}".encode()).hexdigest()[:8], 16)
        variation = seed % 10

        title = f"{title_base}: Empirical Study #{variation} on Attack Mitigation"
        body = (
            f"{desc_base} We present concrete attack vectors, PoC implementations, "
            f"and formal security verification proofs (Variation {variation})."
        )
        corpus[doc_id] = {
            "id": doc_id,
            "title": title,
            "text": body,
            "tags": [tag, "security", f"cwe-{100 + variation}"],
        }
    return corpus


_CTI_BENCH_QUERY_SPECS = [
    (
        "Q-CTI-01",
        "zero trust mutual tls continuous authentication microsegmentation",
        "zero-trust",
    ),
    (
        "Q-CTI-02",
        "prompt injection jailbreak adversarial attacks on LLM agents",
        "llm-security",
    ),
    (
        "Q-CTI-03",
        "lattice based post quantum cryptography kyber ml-kem",
        "cryptography",
    ),
    (
        "Q-CTI-04",
        "transient execution branch target buffer spectre cache side channel",
        "hardware-security",
    ),
    (
        "Q-CTI-05",
        "software supply chain typosquatting dependency confusion provenance",
        "supply-chain",
    ),
    (
        "Q-CTI-06",
        "evasive ransomware living off the land binaries process hollowing",
        "malware-evasion",
    ),
    (
        "Q-CTI-07",
        "policy enforcement identity aware proxy zero trust authorization",
        "zero-trust",
    ),
    (
        "Q-CTI-08",
        "system prompt leakage recursive prompt hijacking safety guardrails",
        "llm-security",
    ),
    (
        "Q-CTI-09",
        "ml-dsa lattice cryptanalysis fault injection mitigation",
        "cryptography",
    ),
    (
        "Q-CTI-10",
        "speculative execution barriers hardware timing attacks meltdown",
        "hardware-security",
    ),
    (
        "Q-CTI-11",
        "slsa provenance attestation malicious post install package registry",
        "supply-chain",
    ),
    (
        "Q-CTI-12",
        "api hooking evasion endpoint detection response bypass",
        "malware-evasion",
    ),
    (
        "Q-CTI-13",
        "continuous identity verification zero trust adaptive access",
        "zero-trust",
    ),
    (
        "Q-CTI-14",
        "multi-agent alignment bypass jailbreak detection defense",
        "llm-security",
    ),
    (
        "Q-CTI-15",
        "quantum resistant digital signatures post quantum lattice security",
        "cryptography",
    ),
]


def _evaluate_doc_relevance(
    doc_data: Dict[str, Any], expected_tag: str, qtext: str
) -> Optional[float]:
    """Calculates relevance score for a document against an expected tag and query."""
    if expected_tag not in doc_data["tags"]:
        return None
    words = qtext.lower().split()[:2]
    title_lower = doc_data["title"].lower()
    for word in words:
        if word in title_lower:
            return 3.0
    return 2.0


def _build_single_query_qrels(
    corpus: Dict[str, Dict[str, Any]], expected_tag: str, qtext: str
) -> Dict[str, float]:
    """Builds ground-truth relevance mappings for a single query."""
    qrel: Dict[str, float] = {}
    for doc_id, doc_data in corpus.items():
        score = _evaluate_doc_relevance(doc_data, expected_tag, qtext)
        if score is not None:
            qrel[doc_id] = score
    return qrel


def _build_cti_queries_and_qrels(
    corpus: Dict[str, Dict[str, Any]], num_queries: int
) -> Tuple[Dict[str, str], Dict[str, Dict[str, float]]]:
    """Builds queries dictionary and qrels relevance judgments for benchmark evaluation."""
    queries: Dict[str, str] = {}
    qrels: Dict[str, Dict[str, float]] = {}

    limit = min(num_queries, len(_CTI_BENCH_QUERY_SPECS))
    for q_idx in range(limit):
        qid, qtext, expected_tag = _CTI_BENCH_QUERY_SPECS[q_idx]
        queries[qid] = qtext
        qrels[qid] = _build_single_query_qrels(corpus, expected_tag, qtext)
    return queries, qrels


def generate_cti_bench_dataset(
    num_docs: int = 120, num_queries: int = 15
) -> BEIRDataset:
    """
    Generates a deterministic, reproducible security CTI benchmark dataset (CTI-Bench).
    Simulates academic papers, threat intelligence reports, and CVE/CWE entity linkages.
    """
    corpus = _build_cti_corpus(num_docs)
    queries, qrels = _build_cti_queries_and_qrels(corpus, num_queries)
    return BEIRDataset(
        name="CTI-Bench-Security-SOTA",
        corpus=corpus,
        queries=queries,
        qrels=qrels,
    )
