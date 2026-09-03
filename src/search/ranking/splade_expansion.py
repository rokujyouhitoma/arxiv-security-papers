#!/usr/bin/env python3
"""
SPLADE-style Lexical Term Expansion for Security Acronyms & Synonyms.
Expands query terms into sparse weighted vocabularies based on security ontologies.
Pure Python, Zero External Dependencies.
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional, Tuple

ACRONYM_ONTOLOGY_MAP: Dict[str, List[str]] = {
    "pqc": [
        "post-quantum",
        "cryptography",
        "lattice",
        "kyber",
        "dilithium",
        "sphincs",
        "falcon",
    ],
    "rop": [
        "return-oriented",
        "programming",
        "gadget",
        "control-flow",
        "cfi",
        "hijack",
    ],
    "aslr": ["address", "space", "layout", "randomization", "exploit", "mitigation"],
    "xss": ["cross-site", "scripting", "sanitization", "dom", "injection"],
    "sqli": ["sql", "injection", "parameterized", "database", "query"],
    "ssrf": ["server-side", "request", "forgery", "internal", "metadata"],
    "dos": ["denial", "service", "amplification", "flooding", "outage"],
    "ddos": ["distributed", "denial", "service", "botnet", "volumetric"],
    "rce": ["remote", "code", "execution", "arbitrary", "takeover"],
    "lpe": ["local", "privilege", "escalation", "root", "kernel"],
    "uaf": ["use-after-free", "memory", "corruption", "heap"],
    "llm": [
        "large",
        "language",
        "model",
        "jailbreak",
        "prompt",
        "injection",
        "transformer",
    ],
    "t1059": ["command", "scripting", "interpreter", "powershell", "bash"],
    "t1190": ["exploit", "public-facing", "application", "vulnerability"],
    "t1068": ["exploitation", "privilege", "escalation"],
    "cwe-787": ["out-of-bounds", "write", "heap", "stack", "overflow"],
    "cwe-89": ["sql", "injection", "rdbms"],
    "cwe-79": ["cross-site", "scripting", "stored", "reflected"],
}


def _calc_base_sparse(tokens: List[str]) -> Dict[str, float]:
    """Calculates log-saturated base frequencies for query tokens."""
    counts: Dict[str, float] = {}
    for token in tokens:
        t_low = token.lower()
        counts[t_low] = counts.get(t_low, 0.0) + 1.0
    return {k: round(math.log(1.0 + cnt), 4) for k, cnt in counts.items()}


def _apply_expansion_weights(
    sparse_vec: Dict[str, float],
    tokens: List[str],
    ontology_map: Dict[str, List[str]],
    weight: float,
) -> None:
    """Applies expansion weights for acronyms and domain concepts."""
    for token in tokens:
        t_low = token.lower()
        for exp in ontology_map.get(t_low, []):
            e_low = exp.lower()
            existing = sparse_vec.get(e_low, 0.0)
            sparse_vec[e_low] = round(existing + weight, 4)


def _sparse_dot(smaller: Dict[str, float], larger: Dict[str, float]) -> float:
    """Computes sparse dot product between smaller and larger dictionaries."""
    total = 0.0
    for k, val in smaller.items():
        if k in larger:
            total += val * larger[k]
    return round(total, 4)


class SpladeTermExpander:
    """
    SPLADE-style sparse lexical expander for domain-specific security literature.
    """

    def __init__(
        self,
        custom_synonyms: Optional[Dict[str, List[str]]] = None,
        expansion_weight: float = 0.5,
    ) -> None:
        self.ontology_map = dict(ACRONYM_ONTOLOGY_MAP)
        if custom_synonyms:
            self.ontology_map.update(custom_synonyms)
        self.expansion_weight = expansion_weight

    def expand(self, query: str) -> Tuple[str, List[Dict[str, Any]]]:
        """
        Expands a text query string with security acronyms and concepts.
        Returns (expanded_query_text, list_of_expansion_details).
        """
        tokens = query.split()
        sparse_vec = self.expand_query(tokens)
        expansions: List[Dict[str, Any]] = []
        for t in tokens:
            t_low = t.lower()
            for exp in self.ontology_map.get(t_low, []):
                expansions.append(
                    {
                        "original_term": t,
                        "expanded_term": exp,
                        "weight": sparse_vec.get(exp.lower(), self.expansion_weight),
                    }
                )
        expanded_terms = [str(e["expanded_term"]) for e in expansions]
        expanded_text = f"{query} {' '.join(expanded_terms)}".strip()
        return expanded_text, expansions

    def expand_query(self, tokens: List[str]) -> Dict[str, float]:
        """
        Takes tokenized query, applies acronym expansion, and generates log-weighted sparse vector.
        Formula: weight = log(1.0 + freq) + (expansion_weight if expanded else 0.0)
        """
        sparse_vec = _calc_base_sparse(tokens)
        _apply_expansion_weights(
            sparse_vec, tokens, self.ontology_map, self.expansion_weight
        )
        return sparse_vec

    @staticmethod
    def compute_sparse_similarity(
        vec_a: Dict[str, float], vec_b: Dict[str, float]
    ) -> float:
        """
        Computes sparse dot product between two sparse term vectors:
        Sum_{t in A intersect B} (vec_a[t] * vec_b[t])
        """
        if not (vec_a and vec_b):
            return 0.0

        if len(vec_a) <= len(vec_b):
            return _sparse_dot(vec_a, vec_b)
        return _sparse_dot(vec_b, vec_a)
