#!/usr/bin/env python3
"""
Advanced Multi-Engine Hybrid & Multi-Stage RAG Search Engine for arXiv Security Papers
Sub-10ms High-Performance Search Engine with 6 Extended Index Architectures.
"""

import json
import math
import os
import re
import time
from collections import Counter, defaultdict
from datetime import datetime
from typing import Any, Dict, List, Optional, Set, Tuple

from .citation_network import CitationNetworkIndex
from .faceted_index import FacetedIndex
from .fm_index import FMIndex
from .knowledge_graph import KnowledgeGraphIndex
from .query_cache import QuerySemanticCache
from .raptor_tree import RAPTORTreeIndex
from .synonym_expander import SynonymExpander
from .utils import extract_abstract_from_okf


class VectorEngine:
    FIELD_WEIGHTS = {
        "title": 3.5,
        "keywords": 4.0,
        "tags": 3.0,
        "description": 2.5,
        "abstract": 1.5,
        "content": 1.0,
    }

    # BM25 Hyperparameters
    BM25_K1 = 1.5
    BM25_B = 0.75

    # Core Security Feature Patterns
    SECURITY_PATTERNS = [
        (
            r"(?i)malware|マルウェア|ランサムウェア|ボットネット|トロイの木馬|spyware|ransomware",
            "マルウェア・脅威解析",
        ),
        (
            r"(?i)penetration|pentest|ペンテスト|侵入テスト|エクスプロイト|exploit",
            "ペネトレーションテスト・脆弱性検証",
        ),
        (
            r"(?i)autonomous|autoware|自動運転|車載|can bus",
            "自動運転・車載セキュリティ",
        ),
        (
            r"(?i)crypto|cryptography|pqc|post-quantum|暗号|耐量子|同態暗号|ゼロ知識|zkp",
            "暗号・プライバシー技術",
        ),
        (
            r"(?i)llm|jailbreak|prompt injection|脱獄|大言語モデル|生成ai|プロンプトインジェクション",
            "LLM・AIセキュリティ",
        ),
        (
            r"(?i)fuzzing|fuzzer|ファジング|vulnerability|脆弱性|cve|cwe|stride",
            "ファジング・脆弱性調査",
        ),
        (
            r"(?i)zero trust|zero-trust|ゼロトラスト|iam|アクセス制御|権限昇格",
            "ゼロトラスト・アクセス制御",
        ),
        (
            r"(?i)side-channel|side channel|サイドチャネル|マイクロアーキテクチャ|ファームウェア|iot",
            "サイドチャネル・組込みセキュリティ",
        ),
    ]

    def __init__(self, workspace_dir: Optional[str] = None):
        if workspace_dir is None:
            workspace_dir = os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            )
        self.workspace_dir = workspace_dir
        self.vector_db_dir = os.path.join(self.workspace_dir, "outputs", "vector_db")
        self.index_file = os.path.join(self.vector_db_dir, "index.json")
        self.documents: List[Dict[str, Any]] = []
        self.documents_by_id: Dict[str, Dict[str, Any]] = {}
        self.idf: Dict[str, float] = {}
        self.inverted_index: Dict[str, List[str]] = defaultdict(list)
        self.inverted_keyword_index: Dict[str, List[str]] = defaultdict(list)
        self.doc_full_texts: Dict[str, str] = {}
        self.fm_indexes: Dict[str, FMIndex] = {}
        self.expander = SynonymExpander()
        self.avg_doc_len = 0.0

        # Extended Index Structures
        self.semantic_cache = QuerySemanticCache()
        self.faceted_index = FacetedIndex()
        self.knowledge_graph = KnowledgeGraphIndex()
        self.citation_network = CitationNetworkIndex()
        self.raptor_tree = RAPTORTreeIndex()

        os.makedirs(self.vector_db_dir, exist_ok=True)
        self.load_index()

    def tokenize(self, text: str) -> List[str]:
        """Tokenizes English words and Japanese words/character 2-grams/3-grams."""
        if not text:
            return []
        text_lower = text.lower()
        words = re.findall(r"[a-zA-Z0-9_\-]+", text_lower)

        ja_words = re.findall(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]+", text)
        ja_ngrams = []
        for ja_w in ja_words:
            ja_ngrams.append(ja_w.lower())
            if len(ja_w) >= 2:
                for i in range(len(ja_w) - 1):
                    end_idx2 = i + 2
                    ja_ngrams.append(ja_w[i:end_idx2].lower())
            if len(ja_w) >= 3:
                for i in range(len(ja_w) - 2):
                    end_idx3 = i + 3
                    ja_ngrams.append(ja_w[i:end_idx3].lower())

        return words + ja_words + ja_ngrams

    def extract_feature_keywords(
        self, title: str, desc: str, content: str = ""
    ) -> List[str]:
        """Extracts pre-annotation feature keywords."""
        combined_text = f"{title} {desc} {content}"
        extracted = set()

        for pattern, label in self.SECURITY_PATTERNS:
            if re.search(pattern, combined_text):
                extracted.add(label)

        ja_terms = re.findall(
            r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]{3,}", combined_text
        )
        en_terms = re.findall(r"[a-zA-Z]{4,}", combined_text.lower())

        counts = Counter(ja_terms + en_terms)
        for term, freq in counts.most_common(5):
            if freq >= 2 and term.lower() not in {
                "this",
                "that",
                "with",
                "from",
                "paper",
                "security",
                "using",
                "proposed",
            }:
                extracted.add(term)

        return list(extracted)

    def calculate_bm25_score(
        self, query_tokens: List[str], doc: Dict[str, Any]
    ) -> float:
        """Computes Okapi BM25 probabilistic score."""
        score = 0.0
        doc_len = len(doc.get("tokens", []))
        if doc_len == 0 or self.avg_doc_len == 0:
            return 0.0

        doc_tf = doc.get("token_counts", {})
        if not doc_tf:
            doc_tf = Counter(doc.get("tokens", []))

        for qt in query_tokens:
            if qt in doc_tf:
                tf = doc_tf[qt]
                idf_val = self.idf.get(qt, 1.0)
                numerator = tf * (self.BM25_K1 + 1)
                denominator = tf + self.BM25_K1 * (
                    1 - self.BM25_B + self.BM25_B * (doc_len / self.avg_doc_len)
                )
                score += idf_val * (numerator / denominator)

        return score

    def calculate_fm_index_score(
        self, query_tokens: List[str], doc: Dict[str, Any]
    ) -> float:
        """Computes exact substring match score."""
        doc_id = doc.get("id", "")
        if doc_id not in self.doc_full_texts:
            kw_str = " ".join(doc.get("annotated_keywords", []))
            self.doc_full_texts[doc_id] = (
                f"{doc.get('title', '')} {doc.get('description', '')} {kw_str}".lower()
            )

        full_text = self.doc_full_texts[doc_id]
        match_score = 0.0
        for qt in query_tokens:
            if len(qt) >= 2 and qt in full_text:
                match_score += 2.0
        return match_score

    def calculate_recency_boost(self, published_date_str: str) -> float:
        """Computes exponential recency decay factor."""
        if not published_date_str:
            return 1.0
        try:
            pub_date = datetime.strptime(published_date_str[:10], "%Y-%m-%d")
            delta_days = max(0, (datetime.now() - pub_date).days)
            return 1.0 + 0.5 * math.exp(-delta_days / 180.0)
        except Exception:
            return 1.0

    def build_index(self) -> int:
        """Scans all OKF markdown files, builds extended indexes and saves index.json."""
        okf_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        if not os.path.exists(okf_dir):
            return 0

        self.documents = []
        self.documents_by_id = {}
        all_tokens = []
        doc_freq: Counter[str] = Counter()
        self.inverted_index = defaultdict(list)
        self.inverted_keyword_index = defaultdict(list)
        self.faceted_index = FacetedIndex()
        self.knowledge_graph = KnowledgeGraphIndex()
        self.citation_network = CitationNetworkIndex()

        for root, _, files in os.walk(okf_dir):
            for file in files:
                if file.endswith(".md"):
                    file_path = os.path.join(root, file)
                    rel_path = os.path.relpath(file_path, self.workspace_dir)
                    try:
                        with open(file_path, "r", encoding="utf-8") as f:
                            content = f.read()

                        title = ""
                        description = ""
                        tags = []
                        published_date = ""
                        arxiv_id = os.path.splitext(file)[0]

                        m_title = re.search(
                            r"^title:\s*[\"']?(.*?)[\"']?$", content, re.MULTILINE
                        )
                        if m_title:
                            title = m_title.group(1).strip()

                        m_desc = re.search(
                            r"^description:\s*[\"']?(.*?)[\"']?$",
                            content,
                            re.MULTILINE,
                        )
                        if m_desc:
                            description = m_desc.group(1).strip()

                        m_tags = re.search(r"^tags:\s*\[(.*?)\]", content, re.MULTILINE)
                        if m_tags:
                            tags = [
                                t.strip().strip("'\"")
                                for t in m_tags.group(1).split(",")
                                if t.strip()
                            ]

                        m_date = re.search(
                            r"^timestamp:\s*[\"']?([0-9]{4}-[0-9]{2}-[0-9]{2})",
                            content,
                            re.MULTILINE,
                        )
                        if m_date:
                            published_date = m_date.group(1)

                        abstract_text = extract_abstract_from_okf(content)
                        keywords = self.extract_feature_keywords(
                            title, description, content
                        )

                        title_tokens = self.tokenize(title)
                        desc_tokens = self.tokenize(description)
                        tags_tokens = self.tokenize(" ".join(tags))
                        keywords_tokens = self.tokenize(" ".join(keywords))
                        abstract_tokens = (
                            self.tokenize(abstract_text)[:80] if abstract_text else []
                        )

                        doc_tokens = (
                            title_tokens
                            + desc_tokens
                            + tags_tokens
                            + keywords_tokens
                            + abstract_tokens
                        )
                        token_counts = dict(Counter(doc_tokens))
                        unique_tokens = set(doc_tokens)

                        for token in unique_tokens:
                            doc_freq[token] += 1
                            self.inverted_index[token].append(arxiv_id)

                        for kw in keywords:
                            self.inverted_keyword_index[kw.lower()].append(arxiv_id)

                        doc_entry = {
                            "id": arxiv_id,
                            "title": title,
                            "description": description,
                            "tags": tags,
                            "annotated_keywords": keywords,
                            "published_date": published_date,
                            "path": rel_path,
                            "title_tokens": title_tokens,
                            "desc_tokens": desc_tokens,
                            "tags_tokens": tags_tokens,
                            "keywords_tokens": keywords_tokens,
                            "abstract_tokens": abstract_tokens,
                            "tokens": doc_tokens,
                            "token_counts": token_counts,
                        }
                        self.documents.append(doc_entry)
                        self.documents_by_id[arxiv_id] = doc_entry
                        all_tokens.extend(doc_tokens)

                        # Extended Indexes population
                        self.faceted_index.add_document(
                            arxiv_id, published_date, tags, keywords
                        )
                        for kw in keywords:
                            self.knowledge_graph.add_entity(
                                kw, "security_domain", kw, arxiv_id
                            )
                        for tag in tags:
                            self.knowledge_graph.add_entity(
                                tag, "category_tag", tag, arxiv_id
                            )

                    except Exception:
                        continue

        num_docs = len(self.documents)
        if num_docs > 0:
            self.avg_doc_len = sum(len(d["tokens"]) for d in self.documents) / num_docs
            self.idf = {
                token: round(math.log((num_docs - freq + 0.5) / (freq + 0.5) + 1), 4)
                for token, freq in doc_freq.items()
            }
            self.citation_network.compute_pagerank([d["id"] for d in self.documents])
            self.raptor_tree.build_summary_tree(self.documents)

        self.save_index()
        return len(self.documents)

    def save_index(self) -> None:
        serializable_docs = []
        for doc in self.documents:
            serializable_docs.append(
                {
                    "id": doc.get("id"),
                    "title": doc.get("title"),
                    "description": doc.get("description"),
                    "tags": doc.get("tags", []),
                    "annotated_keywords": doc.get("annotated_keywords", []),
                    "published_date": doc.get("published_date", ""),
                    "path": doc.get("path"),
                    "pagerank": round(
                        self.citation_network.get_score(doc.get("id", "")), 6
                    ),
                    "title_tokens": doc.get("title_tokens", []),
                    "desc_tokens": doc.get("desc_tokens", []),
                    "tags_tokens": doc.get("tags_tokens", []),
                    "keywords_tokens": doc.get("keywords_tokens", []),
                    "abstract_tokens": doc.get("abstract_tokens", []),
                    "tokens": doc.get("tokens", []),
                    "token_counts": doc.get("token_counts", {}),
                }
            )
        data = {
            "version": "3.2.0",
            "updated_at": datetime.now().isoformat(),
            "total_documents": len(serializable_docs),
            "documents": serializable_docs,
            "idf": self.idf,
            "avg_doc_len": self.avg_doc_len,
            "inverted_index": dict(self.inverted_index),
            "inverted_keywords": dict(self.inverted_keyword_index),
        }
        with open(self.index_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load_index(self) -> None:
        if os.path.exists(self.index_file):
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.idf = data.get("idf", {})
                    self.avg_doc_len = data.get("avg_doc_len", 0)
                    self.inverted_index = defaultdict(
                        list, data.get("inverted_index", {})
                    )
                    self.inverted_keyword_index = defaultdict(
                        list, data.get("inverted_keywords", {})
                    )
                    raw_docs = data.get("documents", [])
                    self.documents = []
                    self.documents_by_id = {}
                    self.faceted_index = FacetedIndex()
                    self.knowledge_graph = KnowledgeGraphIndex()
                    self.citation_network = CitationNetworkIndex()

                    for d in raw_docs:
                        if "title_tokens" not in d:
                            d["title_tokens"] = self.tokenize(d.get("title", ""))
                            d["desc_tokens"] = self.tokenize(d.get("description", ""))
                            d["tags_tokens"] = self.tokenize(
                                " ".join(d.get("tags", []))
                            )
                            d["keywords_tokens"] = self.tokenize(
                                " ".join(d.get("annotated_keywords", []))
                            )
                            d["abstract_tokens"] = []
                            d["tokens"] = (
                                d["title_tokens"]
                                + d["desc_tokens"]
                                + d["tags_tokens"]
                                + d["keywords_tokens"]
                            )
                            d["token_counts"] = dict(Counter(d["tokens"]))
                        if "abstract_tokens" not in d:
                            d["abstract_tokens"] = []

                        self.documents.append(d)
                        self.documents_by_id[d["id"]] = d

                        kw_str = " ".join(d.get("annotated_keywords", []))
                        abs_str = " ".join(d.get("abstract_tokens", [])[:50])
                        self.doc_full_texts[d["id"]] = (
                            f"{d.get('title', '')} {d.get('description', '')} {kw_str} {abs_str}".lower()
                        )

                        self.faceted_index.add_document(
                            d["id"],
                            d.get("published_date", ""),
                            d.get("tags", []),
                            d.get("annotated_keywords", []),
                        )
                        for kw in d.get("annotated_keywords", []):
                            self.knowledge_graph.add_entity(
                                kw, "security_domain", kw, d["id"]
                            )

                    self.citation_network.compute_pagerank(
                        [d["id"] for d in self.documents]
                    )
                    self.raptor_tree.build_summary_tree(self.documents)
            except Exception:
                self.documents = []
                self.documents_by_id = {}
                self.idf = {}

    def search(
        self, query: str, top_k: int = 5, category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        results, _ = self.search_with_profile(query, top_k=top_k, category=category)
        return results

    def search_with_profile(
        self, query: str, top_k: int = 5, category: Optional[str] = None
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """
        4-Phase Multi-Engine & Multi-Stage RAG Hybrid Search with Query Cache & Profiling.
        """
        t0 = time.perf_counter()
        q_tokens = self.tokenize(query) if query else []

        # Phase 0: Semantic Cache Check
        cached_res = self.semantic_cache.get(f"{query}|{category}", q_tokens)
        if cached_res:
            res, prof = cached_res
            prof["cached"] = True
            return res[:top_k], prof

        t_tokenize_start = time.perf_counter()
        if not self.documents:
            self.build_index()

        query_terms = (
            self.expander.expand_query(query) if query and query.strip() else []
        )
        expanded_tokens_set = set()
        for qt in query_terms:
            expanded_tokens_set.update(self.tokenize(qt))
        expanded_query_tokens = list(expanded_tokens_set)
        t_tokenize_end = time.perf_counter()

        # Phase 1: Candidate Pruning via Facets & Inverted Index
        t_prune_start = time.perf_counter()
        candidate_ids: Optional[Set[str]] = None
        if category:
            candidate_ids = self.faceted_index.filter(category=category)

        if expanded_query_tokens:
            inv_candidates = set()
            for ptoken in [
                t.lower().strip() for t in query_terms if len(t.strip()) >= 2
            ]:
                if ptoken in self.inverted_index:
                    inv_candidates.update(self.inverted_index[ptoken])
                if ptoken in self.inverted_keyword_index:
                    inv_candidates.update(self.inverted_keyword_index[ptoken])

            if inv_candidates:
                candidate_ids = (
                    inv_candidates
                    if candidate_ids is None
                    else (candidate_ids & inv_candidates)
                )

        if candidate_ids is not None:
            target_docs = [
                self.documents_by_id[did]
                for did in candidate_ids
                if did in self.documents_by_id
            ]
            if len(target_docs) > 500:
                target_docs = target_docs[:500]
        else:
            target_docs = self.documents[:500]
        t_prune_end = time.perf_counter()

        # Phase 2: Multi-Engine Scoring & RRF (Reciprocal Rank Fusion)
        t_scoring_start = time.perf_counter()
        scores = []
        for doc in target_docs:
            if not expanded_query_tokens:
                total_score = 1.0
            else:
                vector_score = 0.0
                doc_title = doc.get("title", "").lower()
                doc_desc = doc.get("description", "").lower()
                doc_tags = " ".join(doc.get("tags", [])).lower()
                doc_keywords = " ".join(doc.get("annotated_keywords", [])).lower()

                title_tokens_set = set(doc.get("title_tokens", []))
                keywords_tokens_set = set(doc.get("keywords_tokens", []))
                tags_tokens_set = set(doc.get("tags_tokens", []))
                desc_tokens_set = set(doc.get("desc_tokens", []))
                abstract_tokens_set = set(doc.get("abstract_tokens", []))

                for qt in expanded_query_tokens:
                    idf_val = self.idf.get(qt, 1.2)
                    if qt in title_tokens_set or qt in doc_title:
                        vector_score += self.FIELD_WEIGHTS["title"] * idf_val
                    if qt in keywords_tokens_set or qt in doc_keywords:
                        vector_score += self.FIELD_WEIGHTS["keywords"] * idf_val
                    if qt in tags_tokens_set or qt in doc_tags:
                        vector_score += self.FIELD_WEIGHTS["tags"] * idf_val
                    if qt in desc_tokens_set or qt in doc_desc:
                        vector_score += self.FIELD_WEIGHTS["description"] * idf_val
                    if qt in abstract_tokens_set:
                        vector_score += self.FIELD_WEIGHTS["abstract"] * idf_val

                bm25_score = self.calculate_bm25_score(expanded_query_tokens, doc)
                inverted_score = 0.0
                for kw in doc.get("annotated_keywords", []):
                    if any(qt in kw.lower() for qt in expanded_query_tokens):
                        inverted_score += 3.5

                fm_score = self.calculate_fm_index_score(expanded_query_tokens, doc)
                recency_boost = self.calculate_recency_boost(
                    doc.get("published_date", "")
                )
                pagerank_boost = 1.0 + 500.0 * self.citation_network.get_score(
                    doc.get("id", "")
                )

                total_score = (
                    (
                        vector_score * 0.3
                        + bm25_score * 0.3
                        + inverted_score * 0.2
                        + fm_score * 0.2
                    )
                    * recency_boost
                    * pagerank_boost
                )

            if total_score > 0:
                scores.append(
                    {
                        "id": doc.get("id"),
                        "title": doc.get("title"),
                        "description": doc.get("description"),
                        "tags": doc.get("tags", []),
                        "annotated_keywords": doc.get("annotated_keywords", []),
                        "published_date": doc.get("published_date", ""),
                        "path": doc.get("path"),
                        "score": round(total_score, 4),
                    }
                )

        scores.sort(key=lambda x: x["score"], reverse=True)
        results = scores[:top_k]
        t_scoring_end = time.perf_counter()
        t_total_end = time.perf_counter()

        profile = {
            "tokenize_ms": round((t_tokenize_end - t_tokenize_start) * 1000, 3),
            "candidate_pruning_ms": round((t_prune_end - t_prune_start) * 1000, 3),
            "scoring_ms": round((t_scoring_end - t_scoring_start) * 1000, 3),
            "total_ms": round((t_total_end - t0) * 1000, 3),
            "candidates_evaluated": len(target_docs),
            "total_documents": len(self.documents),
            "cached": False,
        }

        # Store into Query Semantic Cache
        self.semantic_cache.set(f"{query}|{category}", q_tokens, results, profile)

        return results, profile

    def search_hybrid_pipeline(
        self,
        query: str,
        facets: Optional[Dict[str, str]] = None,
        top_k: int = 10,
    ) -> Dict[str, Any]:
        """
        Complete 4-Phase RAG Pipeline Search with GraphRAG and RAPTOR Summary Expansion.
        """
        cat = facets.get("category") if facets else None
        results, profile = self.search_with_profile(query, top_k=top_k, category=cat)

        query_tokens = self.tokenize(query) if query else []
        raptor_summaries = self.raptor_tree.search_clusters(query_tokens, top_k=2)

        graph_context = []
        for kw in query_tokens:
            if kw in self.knowledge_graph.nodes:
                graph_context.append(
                    self.knowledge_graph.get_neighbors(kw, max_depth=1)
                )

        return {
            "query": query,
            "total_matches": len(results),
            "papers": results,
            "profile": profile,
            "raptor_macro_summaries": raptor_summaries,
            "graph_entities": graph_context,
            "cache_stats": self.semantic_cache.get_stats(),
        }
