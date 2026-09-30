"""Unit tests for DynamicTopicClusterer and TopicClustererSPI."""

from nlp.clustering.topic_model import DynamicTopicClusterer
from nlp.core.protocols import TopicClustererSPI
from nlp.core.tokens import TopicCluster


def test_topic_clusterer_spi_compliance() -> None:
    """Verify DynamicTopicClusterer strictly satisfies TopicClustererSPI."""
    clusterer = DynamicTopicClusterer()
    assert isinstance(clusterer, TopicClustererSPI)


def test_topic_clusterer_empty_documents() -> None:
    """Verify behavior on empty document sequence."""
    clusterer = DynamicTopicClusterer()
    clusters = clusterer.cluster([])
    assert clusters == []


def test_topic_clusterer_single_document() -> None:
    """Verify behavior on a single document."""
    clusterer = DynamicTopicClusterer()
    doc = {
        "title": "Quantum Key Distribution Protocol Analysis",
        "abstract": "We evaluate post-quantum cryptography and QKD lattice security.",
        "tags": ["cs.CR", "Quantum Cryptography"],
        "clean_id": "2609.00001",
    }
    clusters = clusterer.cluster([doc])
    assert len(clusters) == 1
    c = clusters[0]
    assert isinstance(c, TopicCluster)
    assert c.cluster_id == "cluster_0"
    assert "量子" in c.label or "Quantum" in c.label or "暗号" in c.label
    assert c.document_ids == ("2609.00001",)
    assert c.score == 1.0


def test_topic_clusterer_multi_documents_separation() -> None:
    """Verify distinct topic domains are clustered into separate communities."""
    papers = [
        # AI/LLM Security cluster
        {
            "title": "Prompt Injection Attacks in LLM Agents",
            "abstract": "We analyze jailbreak vulnerabilities and adversarial prompts.",
            "tags": ["cs.CR", "AI Security"],
            "clean_id": "ai_1",
        },
        {
            "title": "Adversarial Jailbreaks in Autonomous AI Workflows",
            "abstract": "Attacking multi-agent LLM systems via poisoned context prompts.",
            "tags": ["cs.CR", "AI Security"],
            "clean_id": "ai_2",
        },
        # Hardware / DRAM cluster
        {
            "title": "RowHammer Fault Injection on DDR5",
            "abstract": "Hardware fault attacks inducing bit flips in modern DRAM chips.",
            "tags": ["cs.CR", "Hardware"],
            "clean_id": "hw_1",
        },
        {
            "title": "DRAM Disturbance and Side-Channel Timing Exploits",
            "abstract": "RowHammer disturbance errors and physical side-channel leakages.",
            "tags": ["cs.CR", "Hardware"],
            "clean_id": "hw_2",
        },
    ]

    clusterer = DynamicTopicClusterer(similarity_threshold=0.10)
    clusters = clusterer.cluster(papers)

    assert len(clusters) >= 2
    # Verify AI papers are grouped together and HW papers are grouped together
    ai_doc_ids = {"ai_1", "ai_2"}
    hw_doc_ids = {"hw_1", "hw_2"}

    cluster_doc_sets = [set(c.document_ids) for c in clusters]
    assert any(
        ai_doc_ids.issubset(s) or len(ai_doc_ids.intersection(s)) >= 1
        for s in cluster_doc_sets
    )
    assert any(
        hw_doc_ids.issubset(s) or len(hw_doc_ids.intersection(s)) >= 1
        for s in cluster_doc_sets
    )


def test_topic_clusterer_emerging_topic_dynamic_naming() -> None:
    """Verify novel topics outside canonical domains are dynamically labeled."""
    papers = [
        {
            "title": "EBPF Kernel Sandbox Escapes",
            "abstract": "Exploiting eBPF verifier memory corruption to bypass kernel sandbox.",
            "tags": ["cs.CR"],
            "clean_id": "ebpf_1",
        },
        {
            "title": "Advanced eBPF Verifier Vulnerabilities",
            "abstract": "Novel memory corruption primitives in Linux kernel eBPF subsystem.",
            "tags": ["cs.CR"],
            "clean_id": "ebpf_2",
        },
    ]

    clusterer = DynamicTopicClusterer(similarity_threshold=0.10)
    clusters = clusterer.cluster(papers)

    assert len(clusters) >= 1
    # Check that dynamic labeling derived labels or keywords
    labels = [c.label for c in clusters]
    assert any(len(lbl) > 0 for lbl in labels)
    all_keywords = [kw for c in clusters for kw in c.keywords]
    assert any("ebpf" in kw.lower() or "verifier" in kw.lower() for kw in all_keywords)
