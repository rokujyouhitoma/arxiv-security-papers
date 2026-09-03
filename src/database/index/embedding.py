#!/usr/bin/env python3
"""
Zero-Dependency Deterministic Text Embedding & Vector Normalization Helper.
Projects natural language text (abstracts, titles, queries) into fixed D-dimensional
Float32 unit vectors using multi-scale subword n-grams, semantic seed projection,
and feature hashing without external ML models.
"""

from __future__ import annotations

import hashlib
import math
import re
from typing import Dict, List, Sequence, Tuple

STOP_WORDS = {
    "a",
    "an",
    "the",
    "and",
    "or",
    "in",
    "on",
    "at",
    "to",
    "for",
    "of",
    "with",
    "by",
    "from",
    "as",
    "is",
    "are",
    "was",
    "were",
    "be",
    "been",
    "this",
    "that",
    "these",
    "those",
    "it",
    "its",
    "we",
    "our",
    "which",
    "can",
    "into",
    "also",
}

SECURITY_CONCEPT_SEEDS: Dict[str, Tuple[str, ...]] = {
    "cryptography": (
        "crypto",
        "cipher",
        "encryption",
        "decryption",
        "hash",
        "signature",
        "pqc",
        "lattice",
        "elliptic",
        "rsa",
        "zero-knowledge",
        "zkp",
        "homomorphic",
    ),
    "web_injection": (
        "injection",
        "sqli",
        "xss",
        "csrf",
        "ssrf",
        "rce",
        "jailbreak",
        "prompt",
        "deserialization",
        "payload",
        "exploit",
        "bypass",
        "adversarial",
    ),
    "network_infrastructure": (
        "network",
        "packet",
        "firewall",
        "ddos",
        "botnet",
        "routing",
        "bgp",
        "dns",
        "vpn",
        "zero-trust",
        "proxy",
        "tls",
        "protocol",
        "perimeter",
    ),
    "malware_binary": (
        "malware",
        "ransomware",
        "trojan",
        "worm",
        "rootkit",
        "shellcode",
        "overflow",
        "rop",
        "heap",
        "stack",
        "memory-corruption",
        "sandbox",
    ),
    "access_control": (
        "authentication",
        "authorization",
        "oauth",
        "rbac",
        "abac",
        "mfa",
        "credential",
        "privilege",
        "token",
        "password",
        "biometric",
        "identity",
    ),
    "hardware_sidechannel": (
        "side-channel",
        "spectre",
        "meltdown",
        "fault",
        "firmware",
        "tpm",
        "enclave",
        "sgx",
        "trustzone",
        "microarchitecture",
        "cache-attack",
    ),
    "audit_vulnerability": (
        "vulnerability",
        "cve",
        "cvss",
        "fuzzing",
        "sanitizer",
        "audit",
        "patch",
        "static-analysis",
        "sbom",
        "supply-chain",
        "taint",
    ),
}


def _hash_slot_and_sign(text: str, dim: int) -> Tuple[int, float]:
    h = int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:16], 16)
    idx = h % dim
    sign = 1.0 if ((h >> 8) & 1) == 0 else -1.0
    return idx, sign


def _compute_cluster_basis(cluster_name: str, dim: int) -> List[float]:
    basis = [0.0] * dim
    for i in range(4):
        slot, sign = _hash_slot_and_sign(f"{cluster_name}_seed_{i}", dim)
        basis[slot] += sign * (1.0 / math.sqrt(4.0))
    return basis


def _score_cluster_match(
    clean_text: str, tokens: List[str], keywords: Tuple[str, ...]
) -> float:
    score = 0.0
    token_set = set(tokens)
    for kw in keywords:
        if kw in token_set:
            score += 1.5
        elif kw in clean_text:
            score += 0.8
    return score


def _vector_norm(v: Sequence[float]) -> float:
    return math.sqrt(sum(a * a for a in v))


def _vector_dot(v1: Sequence[float], v2: Sequence[float]) -> float:
    return sum(a * b for a, b in zip(v1, v2))


def _expand_hyphenated_token(tok: str, out: List[str]) -> None:
    if "-" in tok or "_" in tok:
        for part in re.split(r"[\-_]+", tok):
            if part:
                out.append(part)


def _extract_all_tokens(clean: str) -> List[str]:
    raw_tokens = re.findall(r"[a-z0-9_\-\.\u3040-\u30ff\u4e00-\u9faf]+", clean)
    tokens: List[str] = []
    for t in raw_tokens:
        tokens.append(t)
        _expand_hyphenated_token(t, tokens)
    return tokens


def _hash_ngram_range(
    clean: str, n: int, dim: int, vec: List[float], weight: float
) -> None:
    limit = min(len(clean), 4096)
    for i in range(limit - n + 1):
        idx, sign = _hash_slot_and_sign(clean[i : i + n], dim)
        vec[idx] += sign * weight


class DeterministicEmbedding:
    """
    Zero-dependency deterministic text embedder and vector normalizer.
    Generates normalized Float32 unit vectors for ANN vector indexing with semantic projection.
    """

    def __init__(self, dim: int = 128) -> None:
        self.dim = dim
        self._cluster_bases: Dict[str, List[float]] = {
            c_name: _compute_cluster_basis(c_name, self.dim)
            for c_name in SECURITY_CONCEPT_SEEDS
        }

    @staticmethod
    def normalize(vector: Sequence[float]) -> Tuple[float, ...]:
        """L2 normalizes a vector into a unit vector (norm = 1.0)."""
        norm_val = _vector_norm(vector)
        if norm_val <= 0.0:
            return tuple(0.0 for _ in range(len(vector)))
        return tuple(x / norm_val for x in vector)

    @staticmethod
    def cosine_similarity(v1: Sequence[float], v2: Sequence[float]) -> float:
        """Computes cosine similarity between two unit or arbitrary Float32 vectors."""
        denom = _vector_norm(v1) * _vector_norm(v2)
        if denom <= 0.0:
            return 0.0
        return float(_vector_dot(v1, v2) / denom)

    def _accumulate_token_features(self, tokens: List[str], vec: List[float]) -> None:
        for token in tokens:
            if token in STOP_WORDS:
                continue
            idx, sign = _hash_slot_and_sign(token, self.dim)
            weight = 1.0 + math.log(1.0 + len(token))
            vec[idx] += sign * weight

    def _accumulate_subword_ngrams(self, clean: str, vec: List[float]) -> None:
        _hash_ngram_range(clean, 3, self.dim, vec, 0.4)
        _hash_ngram_range(clean, 4, self.dim, vec, 0.3)

    def _project_semantic_seeds(
        self, clean_text: str, tokens: List[str], vec: List[float]
    ) -> None:
        for c_name, keywords in SECURITY_CONCEPT_SEEDS.items():
            match_weight = _score_cluster_match(clean_text, tokens, keywords)
            if match_weight > 0.0:
                basis = self._cluster_bases[c_name]
                for i in range(self.dim):
                    vec[i] += basis[i] * match_weight * 2.5

    def embed_text(self, text: str) -> Tuple[float, ...]:
        """
        Embeds a text string into a normalized D-dimensional float vector.
        Uses multi-scale feature hashing (tokens + character n-grams) and semantic seed projection.
        """
        if not text:
            return tuple(0.0 for _ in range(self.dim))

        vec = [0.0] * self.dim
        clean = text.lower()[:8192].strip()
        tokens = _extract_all_tokens(clean)

        self._accumulate_token_features(tokens, vec)
        self._accumulate_subword_ngrams(clean, vec)
        self._project_semantic_seeds(clean, tokens, vec)

        return self.normalize(vec)

    def batch_embed(self, texts: Sequence[str]) -> List[Tuple[float, ...]]:
        """Embeds a list of texts in batch."""
        return [self.embed_text(t) for t in texts]
