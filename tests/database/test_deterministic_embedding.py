#!/usr/bin/env python3
"""
Unit tests and semantic benchmark for enhanced Pure-Python DeterministicEmbedding.
Verifies multi-scale subword n-gram hashing, semantic seed projection, and cosine similarity.
"""

import math
import time

from database.index.embedding import DeterministicEmbedding


def test_embedding_dimensions_and_determinism():
    embedder = DeterministicEmbedding(dim=128)
    text = "Zero Trust Architecture and Microsegmentation in Cloud Infrastructure"

    v1 = embedder.embed_text(text)
    v2 = embedder.embed_text(text)

    assert len(v1) == 128
    assert v1 == v2  # Exact determinism

    # L2 unit normalization check
    norm = math.sqrt(sum(x * x for x in v1))
    assert abs(norm - 1.0) < 1e-5


def test_embedding_empty_text():
    embedder = DeterministicEmbedding(dim=64)
    v = embedder.embed_text("")
    assert len(v) == 64
    assert all(x == 0.0 for x in v)


def test_semantic_similarity_clusters_and_separation():
    embedder = DeterministicEmbedding(dim=128)

    # Concept A: LLM Prompt Injection & Jailbreak (Security Group: web_injection)
    text_a1 = "Prompt injection attacks and jailbreak vulnerabilities in LLMs"
    text_a2 = (
        "Adversarial prompt bypass and security payload injection in language models"
    )

    # Concept B: Unrelated non-security topic (Cooking)
    text_b = "Traditional Italian pasta carbonara recipe with egg yolk and guanciale"

    v_a1 = embedder.embed_text(text_a1)
    v_a2 = embedder.embed_text(text_a2)
    v_b = embedder.embed_text(text_b)

    sim_related = DeterministicEmbedding.cosine_similarity(v_a1, v_a2)
    sim_unrelated = DeterministicEmbedding.cosine_similarity(v_a1, v_b)

    # Assert related concepts have high cosine similarity (> 0.60)
    assert sim_related > 0.60, f"Expected high similarity, got {sim_related}"

    # Assert unrelated text has low cosine similarity (< 0.25)
    assert sim_unrelated < 0.25, f"Expected low similarity, got {sim_unrelated}"

    # Assert separation margin >= 0.35 (DoD)
    margin = sim_related - sim_unrelated
    assert margin >= 0.35, f"Expected margin >= 0.35, got {margin}"


def test_subword_and_hyphenation_resilience():
    embedder = DeterministicEmbedding(dim=128)

    # Hyphenated vs unhyphenated security terms
    v_hyphen = embedder.embed_text("zero-trust network perimeter")
    v_spaced = embedder.embed_text("zero trust network perimeter")

    sim = DeterministicEmbedding.cosine_similarity(v_hyphen, v_spaced)
    assert sim > 0.85, f"Expected high similarity for subwords, got {sim}"


def test_embedding_latency_performance():
    embedder = DeterministicEmbedding(dim=128)
    sample_text = (
        "Quantum key distribution and post-quantum lattice cryptography with "
        "side-channel analysis protection in embedded secure enclaves."
    )

    # Warmup
    embedder.embed_text(sample_text)

    # Measure 100 queries
    t0 = time.perf_counter()
    for _ in range(100):
        embedder.embed_text(sample_text)
    total_elapsed = time.perf_counter() - t0
    avg_ms = (total_elapsed / 100.0) * 1000.0

    # Must be well under 5ms (DoD)
    assert avg_ms < 5.0, f"Expected < 5ms per query, got {avg_ms:.2f}ms"


def test_batch_embed():
    embedder = DeterministicEmbedding(dim=64)
    texts = [
        "Malware analysis and sandbox evasion",
        "Ransomware encryption and rootkit detection",
    ]
    batch = embedder.batch_embed(texts)
    assert len(batch) == 2
    assert len(batch[0]) == 64
    assert len(batch[1]) == 64
