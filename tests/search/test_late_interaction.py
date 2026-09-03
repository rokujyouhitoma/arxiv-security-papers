from src.search.ranking.late_interaction import (
    compute_maxsim,
    cosine_similarity,
    dot_product,
)
from src.search.ranking.splade_expansion import SpladeTermExpander
from src.search.vector_engine import VectorEngine


def test_cosine_similarity_and_dot_product():
    v1 = (1.0, 0.0, 0.0)
    v2 = (1.0, 0.0, 0.0)
    v3 = (0.0, 1.0, 0.0)

    assert dot_product(v1, v2) == 1.0
    assert dot_product(v1, v3) == 0.0
    assert cosine_similarity(v1, v2) == 1.0
    assert cosine_similarity(v1, v3) == 0.0
    assert cosine_similarity((0.0, 0.0), (0.0, 0.0)) == 0.0


def test_compute_maxsim():
    q_emb = [
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    d_emb = [
        (1.0, 0.0, 0.0),
        (0.0, 0.5, 0.5),
        (0.0, 0.8, 0.6),
    ]
    sim = compute_maxsim(q_emb, d_emb)
    assert round(sim, 4) == 0.9

    assert compute_maxsim([], d_emb) == 0.0
    assert compute_maxsim(q_emb, []) == 0.0


def test_splade_term_expansion():
    expander = SpladeTermExpander()
    query = "Evaluating LLM Prompt Injection and Jailbreak"
    expanded_text, expansions = expander.expand(query)

    assert "llm" in expanded_text.lower()
    assert len(expansions) > 0
    expanded_terms = [item["expanded_term"] for item in expansions]
    assert any("language" in term or "prompt" in term for term in expanded_terms)


def test_vector_engine_late_interaction():
    engine = VectorEngine(lazy=True)
    engine.documents = [
        {
            "id": "2401.0001",
            "title": "Adversarial Prompt Injection in LLMs",
            "description": "Analysis of jailbreak attacks against large language models and defense mechanisms.",
            "tokens": [
                "adversarial",
                "prompt",
                "injection",
                "llms",
                "jailbreak",
                "models",
            ],
            "token_counts": {"adversarial": 1, "prompt": 1, "injection": 1, "llms": 1},
        },
        {
            "id": "2401.0002",
            "title": "Quantum Key Distribution Protocols",
            "description": "Post-quantum cryptography and lattice-based key exchange mechanisms.",
            "tokens": [
                "quantum",
                "key",
                "distribution",
                "post-quantum",
                "cryptography",
            ],
            "token_counts": {"quantum": 1, "key": 1, "distribution": 1},
        },
    ]
    engine.documents_by_id = {d["id"]: d for d in engine.documents}
    engine.avg_doc_len = 5.0
    engine.idf = {"prompt": 1.5, "injection": 1.5, "quantum": 1.5}

    results = engine.search_late_interaction("prompt injection jailbreak", top_k=2)
    assert len(results) > 0
    assert results[0]["id"] == "2401.0001"
    assert "maxsim_score" in results[0]
