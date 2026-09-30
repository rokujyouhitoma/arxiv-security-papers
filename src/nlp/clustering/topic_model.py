"""Dynamic Topic Clustering Engine conforming to TopicClustererSPI.

Performs pure-Python TF-IDF vectorization, pairwise cosine similarity graph
construction, and Louvain modularity optimization to autonomously identify
known and emerging cybersecurity topics.
Zero external dependencies, Xenon CC <= 3, and Mypy strict compliant.
"""

from __future__ import annotations

import math
import re
from collections import defaultdict
from typing import Any, Dict, List, Optional, Sequence, Tuple

from core.structures.community import LouvainCommunityDetector
from nlp.core.protocols import TopicClustererSPI
from nlp.core.tokens import TopicCluster
from nlp.lexicon.security_thesaurus import SecurityThesaurus
from nlp.lexicon.stop_words import STOPWORDS

_WORD_PATTERN = re.compile(r"[a-zA-Z0-9_\-\.]{2,}")

_CANONICAL_DOMAIN_MAP: List[Tuple[str, Tuple[str, ...]]] = [
    (
        "AI/LLM セキュリティ & 敵対的攻撃",
        (
            "llm",
            "prompt injection",
            "jailbreak",
            "agent",
            "adversarial",
            "rag",
            "poisoning",
            "backdoor",
        ),
    ),
    (
        "ハードウェア & 低レイヤ物理セキュリティ",
        (
            "rowhammer",
            "fault injection",
            "dram",
            "hardware",
            "side-channel",
            "spectre",
            "meltdown",
        ),
    ),
    (
        "量子暗号 & ゼロ知識証明技術",
        (
            "quantum",
            "qkd",
            "post-quantum",
            "lattice",
            "zero-knowledge",
            "cryptography",
            "pqc",
            "zkp",
        ),
    ),
    (
        "ソフトウェア脆弱性 & Web3/DeFi",
        (
            "smart contract",
            "defi",
            "blockchain",
            "vulnerability",
            "fuzzing",
            "malware",
            "exploit",
        ),
    ),
    (
        "ネットワークセキュリティ & 通信耐障害性",
        (
            "network",
            "ipsec",
            "ddos",
            "traffic",
            "quic",
            "routing",
            "firewall",
            "dns",
        ),
    ),
    (
        "プライバシー保護 & 匿名化技術",
        (
            "privacy",
            "anonymity",
            "differential privacy",
            "federated learning",
            "tracking",
        ),
    ),
]


def _join_field_items(doc: Dict[str, Any], key: str) -> str:
    """Safely extract and join list items from a document key."""
    items = doc.get(key)
    if not isinstance(items, list):
        return ""
    return " ".join(str(item) for item in items)


def _extract_document_text(doc: Dict[str, Any]) -> str:
    """Combines document fields into search text."""
    title = str(doc.get("title") or "")
    abstract = str(doc.get("abstract") or "")
    tags = _join_field_items(doc, "tags")
    keyphrases = _join_field_items(doc, "keyphrases")
    return f"{title} {abstract} {tags} {keyphrases}".lower()


def _tokenize_text(text: str) -> List[str]:
    """Tokenize text into cleaned words excluding stopwords."""
    matches = _WORD_PATTERN.findall(text)
    return [m for m in matches if len(m) > 2 and not m.isdigit() and m not in STOPWORDS]


def _compute_term_frequencies(tokens: List[str]) -> Dict[str, float]:
    """Compute term frequency (TF) for a token list."""
    if not tokens:
        return {}
    counts: Dict[str, int] = defaultdict(int)
    for tok in tokens:
        counts[tok] += 1
    total = float(len(tokens))
    return {k: v / total for k, v in counts.items()}


def _compute_doc_frequencies(tokenized_docs: List[List[str]]) -> Dict[str, int]:
    """Compute document frequencies (DF) across all documents."""
    df: Dict[str, int] = defaultdict(int)
    for tokens in tokenized_docs:
        for term in set(tokens):
            df[term] += 1
    return df


def _build_tfidf_vector(
    tf: Dict[str, float], df: Dict[str, int], total_docs: int
) -> Dict[str, float]:
    """Compute normalized TF-IDF vector for a single document."""
    vec: Dict[str, float] = {}
    norm_sq = 0.0
    for term, term_freq in tf.items():
        doc_freq = df.get(term, 1)
        idf = math.log((1.0 + total_docs) / (1.0 + doc_freq)) + 1.0
        val = term_freq * idf
        vec[term] = val
        norm_sq += val * val

    if norm_sq <= 0.0:
        return {}
    norm = math.sqrt(norm_sq)
    return {k: v / norm for k, v in vec.items()}


def _cosine_similarity(vec1: Dict[str, float], vec2: Dict[str, float]) -> float:
    """Compute cosine similarity between two unit vectors."""
    if len(vec1) > len(vec2):
        vec1, vec2 = vec2, vec1
    sim = 0.0
    for term, val in vec1.items():
        if term in vec2:
            sim += val * vec2[term]
    return sim


def _build_similarity_graph(
    vectors: List[Dict[str, float]], doc_ids: List[str], threshold: float
) -> Dict[str, Dict[str, float]]:
    """Construct adjacency matrix graph using pairwise cosine similarities."""
    adj: Dict[str, Dict[str, float]] = {did: {} for did in doc_ids}
    n = len(doc_ids)
    for i in range(n):
        id_i = doc_ids[i]
        vec_i = vectors[i]
        for j in range(i + 1, n):
            id_j = doc_ids[j]
            sim = _cosine_similarity(vec_i, vectors[j])
            if sim >= threshold:
                adj[id_i][id_j] = sim
                adj[id_j][id_i] = sim
    return adj


def _score_domain_match(cluster_text: str, domain_keywords: Tuple[str, ...]) -> int:
    """Score how well a cluster text matches a canonical domain's keywords."""
    score = 0
    for kw in domain_keywords:
        if kw in cluster_text:
            score += 1
    return score


def _match_canonical_domain(cluster_text: str) -> Optional[str]:
    """Match cluster text to standard security domains if score threshold met."""
    best_domain: Optional[str] = None
    best_score = 0
    for domain_name, kw_tuple in _CANONICAL_DOMAIN_MAP:
        score = _score_domain_match(cluster_text, kw_tuple)
        if score > best_score:
            best_score = score
            best_domain = domain_name
    return best_domain if best_score >= 1 else None


def _format_dynamic_label(
    top_terms: Tuple[str, ...], thesaurus: SecurityThesaurus
) -> str:
    """Generate dynamic Japanese cluster label from top terms using thesaurus."""
    if not top_terms:
        return "システムセキュリティ & 基盤防御"

    ja_parts: List[str] = []
    for term in top_terms[:2]:
        translated = thesaurus.lookup_japanese(term)
        ja_parts.append(translated if translated else term.capitalize())
    return " & ".join(ja_parts)


def _resolve_cluster_label(
    cluster_docs: List[Dict[str, Any]],
    top_terms: Tuple[str, ...],
    thesaurus: SecurityThesaurus,
) -> str:
    """Resolve cluster label prioritizing canonical domains, then dynamic naming."""
    combined_text = " ".join(_extract_document_text(d) for d in cluster_docs)
    matched = _match_canonical_domain(combined_text)
    if matched:
        return matched
    return _format_dynamic_label(top_terms, thesaurus)


def _extract_top_cluster_terms(
    cluster_indices: List[int], vectors: List[Dict[str, float]], top_k: int = 3
) -> Tuple[str, ...]:
    """Extract top scoring terms aggregated over a cluster."""
    aggregated: Dict[str, float] = defaultdict(float)
    for idx in cluster_indices:
        for term, val in vectors[idx].items():
            aggregated[term] += val

    sorted_terms = sorted(aggregated.items(), key=lambda x: x[1], reverse=True)
    return tuple(term for term, _ in sorted_terms[:top_k])


def _derive_doc_id(doc: Dict[str, Any], idx: int) -> str:
    """Derive clean unique document ID string."""
    return str(doc.get("clean_id") or doc.get("arxiv_id") or f"doc_{idx}")


class DynamicTopicClusterer(TopicClustererSPI):
    """Dynamic Topic Clusterer implementing TopicClustererSPI.

    Constructs TF-IDF representations, builds pairwise similarity graphs,
    and clusters documents using Louvain modularity optimization.
    """

    def __init__(
        self,
        similarity_threshold: float = 0.15,
        resolution: float = 1.0,
        thesaurus: Optional[SecurityThesaurus] = None,
    ) -> None:
        """Initialize clusterer with similarity threshold and resolution."""
        self._similarity_threshold = similarity_threshold
        self._resolution = resolution
        self._thesaurus = thesaurus if thesaurus is not None else SecurityThesaurus()
        self._detector = LouvainCommunityDetector()

    def _prepare_vectors(
        self, documents: Sequence[Dict[str, Any]]
    ) -> Tuple[List[str], List[Dict[str, float]]]:
        """Tokenize documents and produce normalized TF-IDF vectors."""
        tokenized = [_tokenize_text(_extract_document_text(d)) for d in documents]
        df = _compute_doc_frequencies(tokenized)
        total_docs = len(documents)
        doc_ids = [_derive_doc_id(d, idx) for idx, d in enumerate(documents)]
        vectors = [
            _build_tfidf_vector(_compute_term_frequencies(tokens), df, total_docs)
            for tokens in tokenized
        ]
        return doc_ids, vectors

    def _cluster_single_or_empty(
        self, documents: Sequence[Dict[str, Any]]
    ) -> List[TopicCluster]:
        """Handle 0 or 1 document edge cases."""
        if not documents:
            return []
        doc = documents[0]
        did = _derive_doc_id(doc, 0)
        tokens = _tokenize_text(_extract_document_text(doc))
        top_k = tuple(sorted(set(tokens), key=tokens.count, reverse=True)[:3])
        label = _resolve_cluster_label([doc], top_k, self._thesaurus)
        return [
            TopicCluster(
                cluster_id="cluster_0",
                label=label,
                keywords=top_k,
                score=1.0,
                document_ids=(did,),
            )
        ]

    def _group_by_community(
        self, partition: Dict[str, int], doc_ids: List[str]
    ) -> Dict[int, List[int]]:
        """Group document indices by their assigned Louvain community."""
        comm_to_indices: Dict[int, List[int]] = defaultdict(list)
        for idx, did in enumerate(doc_ids):
            comm = partition.get(did, idx)
            comm_to_indices[comm].append(idx)
        return comm_to_indices

    def _build_topic_clusters(
        self,
        comm_to_indices: Dict[int, List[int]],
        documents: Sequence[Dict[str, Any]],
        doc_ids: List[str],
        vectors: List[Dict[str, float]],
    ) -> List[TopicCluster]:
        """Construct TopicCluster instances from community groupings."""
        clusters: List[TopicCluster] = []
        sorted_comms = sorted(
            comm_to_indices.items(), key=lambda kv: len(kv[1]), reverse=True
        )

        for c_id, indices in enumerate(sorted_comms, start=1):
            comm_num, doc_idx_list = indices
            c_docs = [documents[i] for i in doc_idx_list]
            c_dids = tuple(doc_ids[i] for i in doc_idx_list)
            top_terms = _extract_top_cluster_terms(doc_idx_list, vectors, top_k=3)
            label = _resolve_cluster_label(c_docs, top_terms, self._thesaurus)
            score = float(len(doc_idx_list))

            clusters.append(
                TopicCluster(
                    cluster_id=f"cluster_{c_id}",
                    label=label,
                    keywords=top_terms,
                    score=score,
                    document_ids=c_dids,
                )
            )
        return clusters

    def cluster(
        self,
        documents: Sequence[Dict[str, Any]],
        num_clusters: Optional[int] = None,
    ) -> List[TopicCluster]:
        """Cluster documents and return identified TopicCluster instances."""
        if len(documents) <= 1:
            return self._cluster_single_or_empty(documents)

        doc_ids, vectors = self._prepare_vectors(documents)
        adj = _build_similarity_graph(vectors, doc_ids, self._similarity_threshold)
        partition = self._detector.detect(adj, resolution=self._resolution)
        comm_to_indices = self._group_by_community(partition, doc_ids)

        return self._build_topic_clusters(comm_to_indices, documents, doc_ids, vectors)
