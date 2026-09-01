#!/usr/bin/env python3
"""
Enterprise Multi-Field Hybrid & Multi-Stage RAG Search Engine Platform (DSN-14).
"""

import json
import logging
import math
import os
import re
import sys
import time
import tracemalloc
from collections import Counter, defaultdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple

from .ingestion import (
    FacetedIndex,
    FMIndex,
    MultiFieldPostingsIndex,
    RAPTORTreeIndex,
    SearchAnalyzer,
)
from .presentation import DynamicHighlighter
from .query import (
    EnterpriseQueryParser,
    QueryClause,
    QueryContext,
    QuerySemanticCache,
    SynonymExpander,
)
from .ranking import CitationNetworkIndex, KnowledgeGraphIndex, ProximityGraphIndex
from .utils import extract_abstract_from_okf
from .vector import (
    DeterministicEmbedding,
    HNSWIndex,
    RRFHybridScorer,
    VectorDBClient,
    VectorDBProtocolHandler,
    VectorStorage,
)


class VectorEngine:
    FIELD_WEIGHTS = {
        "title": 4.0,
        "author": 3.5,
        "keywords": 3.0,
        "tags": 2.5,
        "description": 2.0,
        "abstract": 2.0,
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

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        lazy: bool = False,
        auto_build: bool = False,
    ):
        if workspace_dir is None:
            workspace_dir = os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            )
        self.workspace_dir = workspace_dir
        self.lazy = lazy
        self.auto_build = auto_build
        self.vector_db_dir = os.path.join(self.workspace_dir, "outputs", "vector_db")
        self.raw_data_dir = os.path.join(self.workspace_dir, "outputs", "raw_data")
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

        # Enterprise Architecture Components
        self.analyzer = SearchAnalyzer()
        self.query_parser = EnterpriseQueryParser(self.FIELD_WEIGHTS)
        self.highlighter = DynamicHighlighter()
        self.multi_field_index = MultiFieldPostingsIndex()

        # Extended Index Structures
        self.semantic_cache = QuerySemanticCache()
        self.faceted_index = FacetedIndex()
        self.knowledge_graph = KnowledgeGraphIndex()
        self.citation_network = CitationNetworkIndex()
        self.raptor_tree = RAPTORTreeIndex()
        self.proximity_graph = ProximityGraphIndex(top_k_neighbors=6)

        # Binary Vector Storage and HNSW Index (Protocol-driven)
        self.embedding = DeterministicEmbedding(dim=128)
        self.hnsw_index = HNSWIndex(dim=128)
        self.rrf_scorer = RRFHybridScorer(k=60)
        self.vector_storage_path = os.path.join(self.vector_db_dir, "vectors.vdb")
        self.hnsw_index_path = os.path.join(self.vector_db_dir, "hnsw_index.json")
        self.vector_storage = VectorStorage(self.vector_storage_path, dim=128)
        self.vector_protocol_handler = VectorDBProtocolHandler(
            storage=self.vector_storage,
            index=self.hnsw_index,
            embedding=self.embedding,
        )
        self.vector_client = VectorDBClient(handler=self.vector_protocol_handler)

        self.search_perf_log_path = os.path.join(
            self.workspace_dir, "outputs", "logs", "search_perf_log.jsonl"
        )
        os.makedirs(self.vector_db_dir, exist_ok=True)
        if not self.lazy:
            self.load_index()

    def tokenize(self, text: str) -> List[str]:
        """Tokenizes text using multi-stage analyzer."""
        return self.analyzer.tokenize(text)

    def _extract_en_ja_keywords(self, combined_text: str, extracted: Set[str]) -> None:
        ja_terms = re.findall(
            r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]{3,}", combined_text
        )
        en_terms = re.findall(r"[a-zA-Z]{4,}", combined_text.lower())
        stop_words = {
            "this",
            "that",
            "with",
            "from",
            "paper",
            "security",
            "using",
            "proposed",
        }
        for term, freq in Counter(ja_terms + en_terms).most_common(5):
            if freq >= 2 and term.lower() not in stop_words:
                extracted.add(term)

    def extract_feature_keywords(
        self, title: str, desc: str, content: str = ""
    ) -> List[str]:
        """Extracts pre-annotation feature keywords."""
        combined_text = f"{title} {desc} {content}"
        extracted: Set[str] = set()

        for pattern, label in self.SECURITY_PATTERNS:
            if re.search(pattern, combined_text):
                extracted.add(label)

        self._extract_en_ja_keywords(combined_text, extracted)
        return list(extracted)

    def _extract_authors_from_meta(self, date_dir: str, clean_id: str) -> List[str]:
        """Extracts authors list from raw_data meta.json if available."""
        if not date_dir:
            return []
        meta_path = os.path.join(self.raw_data_dir, date_dir, f"{clean_id}_meta.json")
        if os.path.exists(meta_path):
            try:
                with open(meta_path, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                    return [str(a) for a in meta.get("authors", [])]
            except Exception:
                pass
        return []

    def _bm25_term_score(self, qt: str, tf: int, doc_len: int) -> float:
        idf_val = self.idf.get(qt, 1.0)
        numerator = tf * (self.BM25_K1 + 1)
        denominator = tf + self.BM25_K1 * (
            1 - self.BM25_B + self.BM25_B * (doc_len / self.avg_doc_len)
        )
        return idf_val * (numerator / denominator)

    def _get_doc_tf(self, doc: Dict[str, Any]) -> Dict[str, int]:
        tf = doc.get("token_counts")
        if tf:
            return tf
        return Counter(doc.get("tokens", []))

    def calculate_bm25_score(
        self, query_tokens: List[str], doc: Dict[str, Any]
    ) -> float:
        """Computes Okapi BM25 probabilistic score."""
        doc_len = len(doc.get("tokens", []))
        if doc_len == 0 or self.avg_doc_len == 0:
            return 0.0

        doc_tf = self._get_doc_tf(doc)
        total = 0.0
        for qt in query_tokens:
            if qt in doc_tf:
                total += self._bm25_term_score(qt, doc_tf[qt], doc_len)
        return total

    def calculate_fm_index_score(
        self, query_tokens: List[str], doc: Dict[str, Any]
    ) -> float:
        """Computes exact substring match score."""
        doc_id = doc.get("id", "")
        if doc_id not in self.doc_full_texts:
            kw_str = " ".join(doc.get("annotated_keywords", []))
            authors_str = " ".join(doc.get("authors", []))
            self.doc_full_texts[doc_id] = (
                f"{doc.get('title', '')} {doc.get('description', '')} {authors_str} {kw_str}".lower()
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

    @staticmethod
    def _extract_field_value(pattern: str, content: str, default: str = "") -> str:
        m = re.search(pattern, content, re.MULTILINE)
        return m.group(1).strip() if m else default

    def _extract_authors(self, content: str, date_dir: str, arxiv_id: str) -> List[str]:
        authors = self._extract_authors_from_meta(date_dir, arxiv_id)
        if not authors:
            raw_auth = self._extract_field_value(r"authors:\s*\[(.*?)\]", content)
            authors = [a.strip().strip("'\"") for a in raw_auth.split(",") if a.strip()]
        return authors

    def _extract_okf_meta(
        self, content: str, date_dir: str, arxiv_id: str
    ) -> tuple[str, str, List[str], List[str], str]:
        title = self._extract_field_value(r"^title:\s*[\"']?(.*?)[\"']?$", content)
        description = self._extract_field_value(
            r"^description:\s*[\"']?(.*?)[\"']?$", content
        )
        published_date = self._extract_field_value(
            r"^timestamp:\s*[\"']?([0-9]{4}-[0-9]{2}-[0-9]{2})", content
        )
        raw_tags = self._extract_field_value(r"^tags:\s*\[(.*?)\]", content)
        tags = [t.strip().strip("'\"") for t in raw_tags.split(",") if t.strip()]
        authors = self._extract_authors(content, date_dir, arxiv_id)
        return title, description, tags, authors, published_date

    def _index_single_okf_file(
        self, file_path: str, date_dir: str, file: str, doc_freq: Counter[str]
    ) -> None:
        rel_path = os.path.relpath(file_path, self.workspace_dir)
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        arxiv_id = os.path.splitext(file)[0]
        title, description, tags, authors, published_date = self._extract_okf_meta(
            content, date_dir, arxiv_id
        )
        abstract_text = extract_abstract_from_okf(content)
        keywords = self.extract_feature_keywords(title, description, content)

        title_tokens = self.tokenize(title)
        desc_tokens = self.tokenize(description)
        tags_tokens = self.tokenize(" ".join(tags))
        authors_tokens = self.tokenize(" ".join(authors))
        keywords_tokens = self.tokenize(" ".join(keywords))
        abstract_tokens = self.tokenize(abstract_text)[:120] if abstract_text else []

        doc_tokens = (
            title_tokens
            + desc_tokens
            + tags_tokens
            + authors_tokens
            + keywords_tokens
            + abstract_tokens
        )
        token_counts = dict(Counter(doc_tokens))
        for token in set(doc_tokens):
            doc_freq[token] += 1

        doc_entry = {
            "id": arxiv_id,
            "title": title,
            "description": description,
            "authors": authors,
            "tags": tags,
            "annotated_keywords": keywords,
            "published_date": published_date,
            "path": rel_path,
            "title_tokens": title_tokens,
            "desc_tokens": desc_tokens,
            "tags_tokens": tags_tokens,
            "authors_tokens": authors_tokens,
            "keywords_tokens": keywords_tokens,
            "abstract_tokens": abstract_tokens,
            "tokens": doc_tokens,
            "token_counts": token_counts,
        }
        self._populate_loaded_doc_indexes(doc_entry, arxiv_id)

    def _init_index_structures(self) -> None:
        self.documents = []
        self.documents_by_id = {}
        self.inverted_index = defaultdict(list)
        self.inverted_keyword_index = defaultdict(list)
        self.multi_field_index = MultiFieldPostingsIndex()
        self.faceted_index = FacetedIndex()
        self.knowledge_graph = KnowledgeGraphIndex()
        self.citation_network = CitationNetworkIndex()
        self.proximity_graph = ProximityGraphIndex(top_k_neighbors=6)
        self.raptor_tree = RAPTORTreeIndex()

    def _post_index_build_steps(self, num_docs: int) -> None:
        if hasattr(self.multi_field_index, "compute_field_statistics"):
            self.multi_field_index.compute_field_statistics(num_docs)
        self.citation_network.compute_pagerank([d["id"] for d in self.documents])
        self.raptor_tree.build_summary_tree(self.documents)

    def _compute_idf_map(
        self, doc_freq: Counter[str], num_docs: int
    ) -> Dict[str, float]:
        return {
            token: round(math.log((num_docs - freq + 0.5) / (freq + 0.5) + 1), 4)
            for token, freq in doc_freq.items()
        }

    def _finalize_index_stats(self, doc_freq: Counter[str]) -> None:
        num_docs = len(self.documents)
        if num_docs == 0:
            return
        self.avg_doc_len = sum(len(d["tokens"]) for d in self.documents) / num_docs
        self.idf = self._compute_idf_map(doc_freq, num_docs)
        self._post_index_build_steps(num_docs)
        self.proximity_graph.build_graph(
            self.documents, dict(self.inverted_keyword_index)
        )

    def _index_files_in_dir(
        self, root: str, files: List[str], doc_freq: Counter[str]
    ) -> None:
        date_dir = os.path.basename(root)
        for file in files:
            if file.endswith(".md"):
                try:
                    self._index_single_okf_file(
                        os.path.join(root, file), date_dir, file, doc_freq
                    )
                except Exception:
                    continue

    def build_index(self) -> int:
        """Scans all OKF files, builds multi-field index and saves index.json."""
        okf_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        if not os.path.exists(okf_dir):
            return 0

        self._init_index_structures()
        doc_freq: Counter[str] = Counter()

        for root, _, files in os.walk(okf_dir):
            self._index_files_in_dir(root, files, doc_freq)

        self._finalize_index_stats(doc_freq)
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
                    "authors": doc.get("authors", []),
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
                    "authors_tokens": doc.get("authors_tokens", []),
                    "keywords_tokens": doc.get("keywords_tokens", []),
                    "abstract_tokens": doc.get("abstract_tokens", []),
                    "tokens": doc.get("tokens", []),
                    "token_counts": doc.get("token_counts", {}),
                }
            )
        data = {
            "version": "3.4.0",
            "updated_at": datetime.now().isoformat(),
            "total_documents": len(serializable_docs),
            "documents": serializable_docs,
            "idf": self.idf,
            "avg_doc_len": self.avg_doc_len,
            "inverted_index": dict(self.inverted_index),
            "inverted_keywords": dict(self.inverted_keyword_index),
            "proximity_graph": dict(self.proximity_graph.graph),
        }
        with open(self.index_file, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)

    def _restore_doc_entry(self, d: Dict[str, Any]) -> Dict[str, Any]:
        if "title_tokens" not in d:
            d["title_tokens"] = self.tokenize(d.get("title", ""))
            d["desc_tokens"] = self.tokenize(d.get("description", ""))
            d["tags_tokens"] = self.tokenize(" ".join(d.get("tags", [])))
            d["authors_tokens"] = self.tokenize(" ".join(d.get("authors", [])))
            d["keywords_tokens"] = self.tokenize(
                " ".join(d.get("annotated_keywords", []))
            )
            d["abstract_tokens"] = []
            d["tokens"] = (
                d["title_tokens"]
                + d["desc_tokens"]
                + d["tags_tokens"]
                + d["authors_tokens"]
                + d["keywords_tokens"]
            )
            d["token_counts"] = dict(Counter(d["tokens"]))
        return d

    def _populate_loaded_doc_indexes(self, d: Dict[str, Any], arxiv_id: str) -> None:
        self.documents.append(d)
        self.documents_by_id[arxiv_id] = d
        self.multi_field_index.add_field_tokens(
            arxiv_id, "title", d.get("title_tokens", [])
        )
        self.multi_field_index.add_field_tokens(
            arxiv_id, "author", d.get("authors_tokens", [])
        )
        self.multi_field_index.add_field_tokens(
            arxiv_id, "abstract", d.get("abstract_tokens", [])
        )
        self.multi_field_index.add_field_tokens(
            arxiv_id, "keywords", d.get("keywords_tokens", [])
        )
        self.multi_field_index.add_field_tokens(
            arxiv_id, "tags", d.get("tags_tokens", [])
        )
        self.faceted_index.add_document(
            arxiv_id,
            d.get("published_date", ""),
            d.get("tags", []),
            d.get("annotated_keywords", []),
        )
        for kw in d.get("annotated_keywords", []):
            self.knowledge_graph.add_entity(kw, "security_domain", kw, arxiv_id)
        for tag in d.get("tags", []):
            self.knowledge_graph.add_entity(tag, "category_tag", tag, arxiv_id)
        for author in d.get("authors", []):
            self.knowledge_graph.add_entity(author, "author", author, arxiv_id)

    def _populate_index_from_dict(
        self, data: Dict[str, Any], max_docs: Optional[int]
    ) -> None:
        self.idf = data.get("idf", {})
        self.avg_doc_len = data.get("avg_doc_len", 0)
        self.inverted_index = defaultdict(list, data.get("inverted_index", {}))
        self.inverted_keyword_index = defaultdict(
            list, data.get("inverted_keywords", {})
        )
        raw_docs = data.get("documents", [])
        if max_docs:
            raw_docs = raw_docs[:max_docs]

        self._init_index_structures()
        self.proximity_graph.graph = defaultdict(list, data.get("proximity_graph", {}))

        for d in raw_docs:
            d_res = self._restore_doc_entry(d)
            self._populate_loaded_doc_indexes(d_res, d_res.get("id", ""))

        self._post_index_build_steps(len(self.documents))

    def load_index(self, max_docs: Optional[int] = None) -> None:
        if not os.path.exists(self.index_file):
            return
        try:
            with open(self.index_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._populate_index_from_dict(data, max_docs)
        except (json.JSONDecodeError, OSError, KeyError, TypeError) as e:
            logging.warning("Failed to load index from %s: %s", self.index_file, e)
            self._init_index_structures()
            self.idf = {}

    def _score_neighbor_candidate(
        self, doc: Dict[str, Any], tid: str
    ) -> Optional[Dict[str, Any]]:
        if tid not in self.documents_by_id:
            return None
        tdoc = self.documents_by_id[tid]
        sim = self.proximity_graph.compute_similarity(doc, tdoc)
        if sim <= 0.05:
            return None
        shared_kw = list(
            set(doc.get("annotated_keywords", []))
            & set(tdoc.get("annotated_keywords", []))
        )
        return {
            "target_id": tid,
            "title": tdoc.get("title", ""),
            "description": tdoc.get("description", ""),
            "similarity": round(sim, 4),
            "shared_keywords": shared_kw,
            "path": tdoc.get("path", ""),
            "published_date": tdoc.get("published_date", ""),
        }

    def _compute_fallback_neighbors(
        self, doc: Dict[str, Any], doc_id: str
    ) -> List[Dict[str, Any]]:
        candidate_ids = set()
        for kw in doc.get("annotated_keywords", []):
            candidate_ids.update(self.inverted_keyword_index.get(kw.lower(), []))
        candidate_ids.discard(doc_id)

        scored = [
            cand
            for tid in list(candidate_ids)[:40]
            if (cand := self._score_neighbor_candidate(doc, tid)) is not None
        ]
        scored.sort(key=lambda x: x["similarity"], reverse=True)
        neighbors = scored[:6]
        self.proximity_graph.graph[doc_id] = neighbors
        return neighbors

    def get_related_papers(self, doc_id: str) -> Dict[str, Any]:
        """Retrieves precomputed nearest neighbors for a paper."""
        doc = self.documents_by_id.get(doc_id)
        if not doc:
            return {"status": "error", "message": f"Paper '{doc_id}' not found."}

        neighbors = self.proximity_graph.get_neighbors(doc_id)
        if not neighbors:
            neighbors = self._compute_fallback_neighbors(doc, doc_id)

        mermaid_str = self.proximity_graph.generate_mermaid_graph(
            doc_id, doc.get("title", "")
        )
        return {
            "status": "success",
            "paper_id": doc_id,
            "title": doc.get("title", ""),
            "related_count": len(neighbors),
            "related_papers": neighbors,
            "mermaid_graph": mermaid_str,
        }

    def search(
        self, query: str, top_k: int = 5, category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        results, _ = self.search_with_profile(query, top_k=top_k, category=category)
        return results

    def prepare_query_context(self, query: str) -> QueryContext:
        """Module 1: Query Understanding & Context Preparation."""
        return self.query_parser.create_context(query, self.expander)

    def _match_prefix_or_fuzzy(
        self, clause: QueryClause, fields: List[str]
    ) -> Set[str]:
        matches: Set[str] = set()
        if clause.is_prefix:
            for fld in fields:
                matches.update(self.multi_field_index.search_prefix(fld, clause.term))
        elif clause.is_fuzzy:
            for fld in fields:
                matches.update(
                    self.multi_field_index.search_fuzzy(
                        fld, clause.term, clause.fuzzy_distance
                    )
                )
        return matches

    def _match_field_postings(self, clause: QueryClause, target_field: str) -> Set[str]:
        matches: Set[str] = set()
        for tt in self.tokenize(clause.term):
            for doc_id, _ in self.multi_field_index.get_postings(target_field, tt):
                matches.add(doc_id)
        return matches

    def _match_inverted_tokens(self, clause: QueryClause) -> Set[str]:
        matches: Set[str] = set()
        for tt in self.tokenize(clause.term):
            if tt in self.inverted_index:
                matches.update(self.inverted_index[tt])
        return matches

    def _match_term_or_inverted(
        self, clause: QueryClause, target_field: Optional[str]
    ) -> Set[str]:
        if target_field:
            return self._match_field_postings(clause, target_field)
        return self._match_inverted_tokens(clause)

    def _match_clause_docs(self, clause: QueryClause) -> Set[str]:
        target_field = clause.field
        if clause.is_prefix or clause.is_fuzzy:
            fields = (
                [target_field]
                if target_field
                else ["title", "author", "keywords", "abstract"]
            )
            return self._match_prefix_or_fuzzy(clause, fields)
        return self._match_term_or_inverted(clause, target_field)

    def _fallback_token_candidates(self, expanded_tokens: List[str]) -> Set[str]:
        inv_candidates: Set[str] = set()
        for pterm in expanded_tokens:
            for ptoken in self.tokenize(pterm):
                if ptoken in self.inverted_index:
                    inv_candidates.update(self.inverted_index[ptoken])
                if ptoken in self.inverted_keyword_index:
                    inv_candidates.update(self.inverted_keyword_index[ptoken])
        return inv_candidates

    def _is_restrictive_clause(self, clause: QueryClause) -> bool:
        return bool(
            clause.is_required or clause.field or clause.is_prefix or clause.is_fuzzy
        )

    def _apply_single_clause_filter(
        self, clause: QueryClause, candidate_ids: Optional[Set[str]]
    ) -> Optional[Set[str]]:
        clause_matches = self._match_clause_docs(clause)
        if self._is_restrictive_clause(clause):
            return (
                clause_matches
                if candidate_ids is None
                else (candidate_ids & clause_matches)
            )
        if clause.is_prohibited and candidate_ids is not None:
            candidate_ids.difference_update(clause_matches)
        return candidate_ids

    def _filter_clause_candidates(
        self, clauses: List[QueryClause], candidate_ids: Optional[Set[str]]
    ) -> Optional[Set[str]]:
        for clause in clauses:
            candidate_ids = self._apply_single_clause_filter(clause, candidate_ids)
        return candidate_ids

    def _resolve_candidate_ids(
        self, ctx: QueryContext, category: Optional[str]
    ) -> Optional[Set[str]]:
        candidate_ids = (
            self.faceted_index.filter(category=category) if category else None
        )
        candidate_ids = self._filter_clause_candidates(ctx.clauses, candidate_ids)
        if candidate_ids is None and ctx.expanded_tokens:
            inv_cands = self._fallback_token_candidates(ctx.expanded_tokens)
            if inv_cands:
                candidate_ids = inv_cands
        return candidate_ids

    def retrieve_candidates(
        self,
        ctx: QueryContext,
        category: Optional[str] = None,
        max_candidates: int = 600,
    ) -> List[Dict[str, Any]]:
        """Module 2: Hybrid Retrieval & Multi-Field Candidate Pruning."""
        candidate_ids = self._resolve_candidate_ids(ctx, category)
        if candidate_ids is not None:
            target_docs = [
                self.documents_by_id[did]
                for did in candidate_ids
                if did in self.documents_by_id
            ]
            return target_docs[:max_candidates]
        return self.documents[:max_candidates]

    def _compute_token_field_score(self, qt: str, doc: Dict[str, Any]) -> float:
        idf_val = self.idf.get(qt, 1.2)
        field_checks = (
            ("title", set(doc.get("title_tokens", [])), doc.get("title", "").lower()),
            (
                "author",
                set(doc.get("authors_tokens", [])),
                " ".join(doc.get("authors", [])).lower(),
            ),
            (
                "keywords",
                set(doc.get("keywords_tokens", [])),
                " ".join(doc.get("annotated_keywords", [])).lower(),
            ),
            (
                "tags",
                set(doc.get("tags_tokens", [])),
                " ".join(doc.get("tags", [])).lower(),
            ),
            (
                "description",
                set(doc.get("desc_tokens", [])),
                doc.get("description", "").lower(),
            ),
            (
                "abstract",
                set(doc.get("abstract_tokens", [])),
                " ".join(doc.get("abstract_tokens", [])).lower(),
            ),
        )
        token_score = 0.0
        for fld, tokens_set, raw_text in field_checks:
            if qt in tokens_set:
                token_score += self.FIELD_WEIGHTS.get(fld, 1.0) * idf_val
            elif len(qt) >= 2 and qt in raw_text:
                token_score += (self.FIELD_WEIGHTS.get(fld, 1.0) * 0.5) * idf_val
        return token_score

    def calculate_multi_field_bm25_score(
        self, query_tokens: List[str], doc: Dict[str, Any]
    ) -> float:
        total_score = 0.0
        for qt in query_tokens:
            total_score += self._compute_token_field_score(qt, doc)
        return total_score

    def _score_single_candidate(
        self,
        doc: Dict[str, Any],
        ctx: QueryContext,
        graph_boosts: Dict[str, float],
        vector_sims: Dict[str, float],
    ) -> float:
        doc_id = doc.get("id", "")
        bm25_score = self.calculate_multi_field_bm25_score(
            ctx.original_tokens, doc
        ) + 0.5 * self.calculate_multi_field_bm25_score(ctx.expanded_tokens, doc)
        fm_score = self.calculate_fm_index_score(ctx.original_tokens, doc)
        pagerank_score = self.citation_network.get_score(doc_id)
        graph_boost = graph_boosts.get(doc_id, 0.0)
        recency = self.calculate_recency_boost(doc.get("published_date", ""))
        vector_sim = vector_sims.get(doc_id, 0.0)

        return (
            (bm25_score * 0.40)
            + (fm_score * 0.15)
            + (pagerank_score * 0.10)
            + (graph_boost * 0.15)
            + (vector_sim * 0.20)
        ) * recency

    def _compute_vector_similarities(
        self, query: str, candidates: List[Dict[str, Any]]
    ) -> Dict[str, float]:
        q_vec = self.embedding.embed_text(query)
        sims: Dict[str, float] = {}
        for doc in candidates:
            did = doc.get("id", "")
            title = doc.get("title", "")
            desc = doc.get("description", "") or doc.get("abstract", "")
            doc_text = f"{title} {desc}"
            d_vec = self.embedding.embed_text(doc_text)
            sim = sum(a * b for a, b in zip(q_vec, d_vec))
            sims[did] = max(0.0, float(sim))
        return sims

    def rerank_candidates(
        self,
        ctx: QueryContext,
        candidates: List[Dict[str, Any]],
        top_k: int = 5,
    ) -> List[Dict[str, Any]]:
        """Module 3: Multi-Stage Scoring & Fusion Ranking."""
        graph_boosts = self.knowledge_graph.get_entity_boosts(ctx.original_tokens)
        vector_sims = self._compute_vector_similarities(ctx.original_query, candidates)

        ranked = []
        for doc in candidates:
            final_score = self._score_single_candidate(
                doc, ctx, graph_boosts, vector_sims
            )
            doc_copy = dict(doc)
            doc_copy["score"] = round(final_score, 4)
            ranked.append(doc_copy)

        ranked.sort(key=lambda x: x["score"], reverse=True)
        return ranked[:top_k]

    def format_presentation(
        self, ctx: QueryContext, ranked_items: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """Module 4: Presentation Engine & Dynamic Snippet Generation."""
        results = []
        for item in ranked_items:
            hl_title = self.highlighter.highlight_text(
                item.get("title", ""), ctx.original_tokens
            )
            hl_desc = self.highlighter.highlight_text(
                item.get("description", ""), ctx.original_tokens
            )
            snippets = self.highlighter.generate_snippets(
                item.get("description", ""), ctx.original_tokens
            )

            res_entry = {
                "id": item.get("id"),
                "title": item.get("title"),
                "highlighted_title": hl_title,
                "description": item.get("description"),
                "highlighted_description": hl_desc,
                "snippets": snippets,
                "authors": item.get("authors", []),
                "tags": item.get("tags", []),
                "annotated_keywords": item.get("annotated_keywords", []),
                "published_date": item.get("published_date"),
                "path": item.get("path"),
                "score": item.get("score", 0.0),
                "pagerank": round(
                    self.citation_network.get_score(item.get("id", "")), 4
                ),
            }
            results.append(res_entry)
        return results

    def log_search_performance(
        self,
        query: str,
        top_k: int,
        category: Optional[str],
        result_count: int,
        profile: Dict[str, Any],
    ) -> None:
        """Module 5: Diagnostic Performance Audit Logging."""
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "query": query,
            "category": category,
            "top_k": top_k,
            "result_count": result_count,
            "performance": profile,
        }
        try:
            os.makedirs(os.path.dirname(self.search_perf_log_path), exist_ok=True)
            with open(self.search_perf_log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        except Exception as e:
            sys.stderr.write(f"[SearchEngine] Failed to write perf log: {e}\n")

    def _execute_search_pipeline(
        self, query: str, top_k: int, category: Optional[str], q_tokens: List[str]
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        t0_wall = time.perf_counter()
        t0_cpu = time.process_time()
        start_mem, _ = tracemalloc.get_traced_memory()

        t_tokenize_start = time.perf_counter()
        ctx = self.prepare_query_context(query)
        t_tokenize_end = time.perf_counter()

        t_prune_start = time.perf_counter()
        target_docs = self.retrieve_candidates(
            ctx, category=category, max_candidates=600
        )
        t_prune_end = time.perf_counter()

        t_scoring_start = time.perf_counter()
        ranked_items = self.rerank_candidates(ctx, target_docs, top_k=top_k)
        t_scoring_end = time.perf_counter()

        results = self.format_presentation(ctx, ranked_items)
        t_total_end = time.perf_counter()
        t_cpu_end = time.process_time()

        end_mem, peak_mem = tracemalloc.get_traced_memory()
        profile = {
            "tokenize_ms": round((t_tokenize_end - t_tokenize_start) * 1000, 3),
            "candidate_pruning_ms": round((t_prune_end - t_prune_start) * 1000, 3),
            "scoring_ms": round((t_scoring_end - t_scoring_start) * 1000, 3),
            "total_ms": round((t_total_end - t0_wall) * 1000, 3),
            "cpu_ms": round((t_cpu_end - t0_cpu) * 1000, 3),
            "peak_memory_kb": round(peak_mem / 1024.0, 3),
            "memory_delta_kb": round((end_mem - start_mem) / 1024.0, 3),
            "candidates_evaluated": len(target_docs),
            "total_documents": len(self.documents),
            "clauses_parsed": len(ctx.clauses),
            "intent": ctx.intent,
            "cached": False,
        }
        self.semantic_cache.set(f"{query}|{category}", q_tokens, results, profile)
        self.log_search_performance(query, top_k, category, len(results), profile)
        return results, profile

    def _check_semantic_cache(
        self, query: str, category: Optional[str], q_tokens: List[str], top_k: int
    ) -> Optional[Tuple[List[Dict[str, Any]], Dict[str, Any]]]:
        cached_res = self.semantic_cache.get(f"{query}|{category}", q_tokens)
        if not cached_res:
            return None
        res, prof = cached_res
        prof["cached"] = True
        return res[:top_k], prof

    def _stop_tracing_if_needed(self, was_tracing: bool) -> None:
        if not was_tracing:
            tracemalloc.stop()

    def _start_tracing_if_needed(self) -> bool:
        was_tracing = tracemalloc.is_tracing()
        if not was_tracing:
            tracemalloc.start()
        tracemalloc.reset_peak()
        return was_tracing

    def search_with_profile(
        self, query: str, top_k: int = 5, category: Optional[str] = None
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """
        Enterprise Multi-Field & Multi-Stage Hybrid Search with Query Parser & Dynamic Highlighter.
        """
        was_tracing = self._start_tracing_if_needed()
        q_tokens = self.tokenize(query) if query else []
        cached = self._check_semantic_cache(query, category, q_tokens, top_k)
        if cached is not None:
            self._stop_tracing_if_needed(was_tracing)
            return cached

        results, profile = self._execute_search_pipeline(
            query, top_k, category, q_tokens
        )
        self._stop_tracing_if_needed(was_tracing)
        return results, profile

    def _extract_hybrid_graph_context(self, query_tokens: List[str]) -> List[Any]:
        graph_context = []
        for kw in query_tokens:
            if kw in self.knowledge_graph.nodes:
                graph_context.append(
                    self.knowledge_graph.get_neighbors(kw, max_depth=1)
                )
        return graph_context

    def search_hybrid_pipeline(
        self,
        query: str,
        facets: Optional[Dict[str, str]] = None,
        top_k: int = 10,
    ) -> Dict[str, Any]:
        """
        Complete Multi-Field Hybrid Pipeline Search with Proximity Graph and RAPTOR.
        """
        cat = facets.get("category") if facets else None
        results, profile = self.search_with_profile(query, top_k=top_k, category=cat)
        query_tokens = self.tokenize(query) if query else []
        raptor_summaries = self.raptor_tree.search_clusters(query_tokens, top_k=2)
        graph_context = self._extract_hybrid_graph_context(query_tokens)
        top_related = (
            self.proximity_graph.get_neighbors(results[0]["id"]) if results else []
        )

        return {
            "query": query,
            "total_matches": len(results),
            "papers": results,
            "profile": profile,
            "top_paper_related": top_related,
            "raptor_macro_summaries": raptor_summaries,
            "graph_entities": graph_context,
            "cache_stats": self.semantic_cache.get_stats(),
        }

    def search_vector_ann(self, query: str, top_k: int = 10) -> List[Dict[str, Any]]:
        """
        Searches nearest neighbor papers strictly via Vector DB Protocol Client.
        """
        matches = self.vector_client.search_knn(text=query, top_k=top_k)
        results = []
        for m in matches:
            idx = m.get("index", -1)
            if 0 <= idx < len(self.documents):
                doc = dict(self.documents[idx])
                doc["vector_similarity"] = m.get("score", 0.0)
                doc["score"] = m.get("score", 0.0)
                results.append(doc)
        return results

    def search_rrf_hybrid(
        self, query: str, top_k: int = 10, category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Executes Lexical BM25 and Semantic Vector search, fused via Reciprocal Rank Fusion (RRF).
        """
        bm25_results, _ = self.search_with_profile(
            query, top_k=top_k * 2, category=category
        )
        vector_results = self.search_vector_ann(query, top_k=top_k * 2)
        return self.rrf_scorer.fuse(bm25_results, vector_results, top_k=top_k)


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="VectorEngine CLI for arxiv-security-papers"
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="Build or rebuild the semantic vector index",
    )
    parser.add_argument("--query", "-q", type=str, default="", help="Query to search")
    parser.add_argument(
        "--top-k", type=int, default=10, help="Number of results to return"
    )
    args = parser.parse_args()

    engine = VectorEngine()
    if args.build:
        print("[VectorEngine] Scanning OKF papers and building search index...")
        count = engine.build_index()
        print(f"[VectorEngine] Successfully indexed {count} documents.")
    elif args.query:
        print(f"[VectorEngine] Querying: {args.query}")
        results, profile = engine.search_with_profile(args.query, top_k=args.top_k)
        print(
            f"[VectorEngine] Found {len(results)} matches (Search time: {profile.get('total_ms', 0):.2f}ms):"
        )
        for i, doc in enumerate(results, 1):
            print(
                f"  {i}. [{doc.get('id')}] {doc.get('title')} (score: {doc.get('score', 0):.4f})"
            )
            print(f"     {doc.get('description', '')[:100]}...")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()


__all__ = [
    "VectorEngine",
    "SynonymExpander",
    "FacetedIndex",
    "FMIndex",
    "RAPTORTreeIndex",
    "SearchAnalyzer",
    "DynamicHighlighter",
    "EnterpriseQueryParser",
    "QueryClause",
    "QueryContext",
    "QuerySemanticCache",
    "CitationNetworkIndex",
    "KnowledgeGraphIndex",
    "ProximityGraphIndex",
    "extract_abstract_from_okf",
]
