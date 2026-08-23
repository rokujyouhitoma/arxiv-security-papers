#!/usr/bin/env python3
"""
Enterprise Multi-Field Hybrid & Multi-Stage RAG Search Engine for arXiv Security Papers.
Sub-10ms High-Performance Search Engine with Multi-Field Postings, Query Parser, and Highlighter.
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

        authors = self._extract_authors_from_meta(date_dir, arxiv_id)
        if not authors:
            raw_auth = self._extract_field_value(r"authors:\s*\[(.*?)\]", content)
            authors = [a.strip().strip("'\"") for a in raw_auth.split(",") if a.strip()]

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
            self.inverted_index[token].append(arxiv_id)

        for kw in keywords:
            self.inverted_keyword_index[kw.lower()].append(arxiv_id)

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

    def build_index(self) -> int:
        """Scans all OKF files, builds multi-field index and saves index.json."""
        okf_dir = os.path.join(self.workspace_dir, "outputs", "okf_papers")
        if not os.path.exists(okf_dir):
            return 0

        self.documents = []
        self.documents_by_id = {}
        doc_freq: Counter[str] = Counter()
        self.inverted_index = defaultdict(list)
        self.inverted_keyword_index = defaultdict(list)
        self.multi_field_index = MultiFieldPostingsIndex()
        self.faceted_index = FacetedIndex()
        self.knowledge_graph = KnowledgeGraphIndex()
        self.citation_network = CitationNetworkIndex()
        self.proximity_graph = ProximityGraphIndex(top_k_neighbors=6)

        for root, _, files in os.walk(okf_dir):
            date_dir = os.path.basename(root)
            for file in files:
                if file.endswith(".md"):
                    file_path = os.path.join(root, file)
                    try:
                        self._index_single_okf_file(file_path, date_dir, file, doc_freq)
                    except Exception:
                        continue

        num_docs = len(self.documents)
        if num_docs > 0:
            self.avg_doc_len = sum(len(d["tokens"]) for d in self.documents) / num_docs
            self.idf = {
                token: round(math.log((num_docs - freq + 0.5) / (freq + 0.5) + 1), 4)
                for token, freq in doc_freq.items()
            }
            self.multi_field_index.compute_field_statistics(num_docs)
            self.citation_network.compute_pagerank([d["id"] for d in self.documents])
            self.raptor_tree.build_summary_tree(self.documents)
            self.proximity_graph.build_graph(
                self.documents, dict(self.inverted_keyword_index)
            )

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

    def load_index(self, max_docs: Optional[int] = None) -> None:
        if not os.path.exists(self.index_file):
            return
        try:
            with open(self.index_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.idf = data.get("idf", {})
            self.avg_doc_len = data.get("avg_doc_len", 0)
            self.inverted_index = defaultdict(list, data.get("inverted_index", {}))
            self.inverted_keyword_index = defaultdict(
                list, data.get("inverted_keywords", {})
            )
            raw_docs = data.get("documents", [])
            if max_docs is not None and max_docs > 0:
                raw_docs = raw_docs[:max_docs]

            self.documents = []
            self.documents_by_id = {}
            self.multi_field_index = MultiFieldPostingsIndex()
            self.faceted_index = FacetedIndex()
            self.knowledge_graph = KnowledgeGraphIndex()
            self.citation_network = CitationNetworkIndex()
            self.proximity_graph = ProximityGraphIndex(top_k_neighbors=6)
            self.proximity_graph.graph = defaultdict(
                list, data.get("proximity_graph", {})
            )

            for d in raw_docs:
                d = self._restore_doc_entry(d)
                arxiv_id = d.get("id", "")
                self._populate_loaded_doc_indexes(d, arxiv_id)

            self.multi_field_index.compute_field_statistics(len(self.documents))
            self.citation_network.compute_pagerank([d["id"] for d in self.documents])
            self.raptor_tree.build_summary_tree(self.documents)
        except (json.JSONDecodeError, OSError, KeyError, TypeError) as e:
            logging.warning("Failed to load index from %s: %s", self.index_file, e)
            self.documents = []
            self.documents_by_id = {}
            self.idf = {}

    def get_related_papers(self, doc_id: str) -> Dict[str, Any]:
        """Retrieves precomputed nearest neighbors for a paper."""
        doc = self.documents_by_id.get(doc_id)
        if not doc:
            return {"status": "error", "message": f"Paper '{doc_id}' not found."}

        neighbors = self.proximity_graph.get_neighbors(doc_id)
        if not neighbors:
            # Fallback on-demand calculation
            kw_list = doc.get("annotated_keywords", [])
            candidate_ids = set()
            for kw in kw_list:
                candidate_ids.update(self.inverted_keyword_index.get(kw.lower(), []))
            candidate_ids.discard(doc_id)
            scored = []
            for tid in list(candidate_ids)[:40]:
                if tid in self.documents_by_id:
                    tdoc = self.documents_by_id[tid]
                    sim = self.proximity_graph.compute_similarity(doc, tdoc)
                    if sim > 0.05:
                        shared_kw = list(
                            set(doc.get("annotated_keywords", []))
                            & set(tdoc.get("annotated_keywords", []))
                        )
                        scored.append(
                            {
                                "target_id": tid,
                                "title": tdoc.get("title", ""),
                                "description": tdoc.get("description", ""),
                                "similarity": round(sim, 4),
                                "shared_keywords": shared_kw,
                                "path": tdoc.get("path", ""),
                                "published_date": tdoc.get("published_date", ""),
                            }
                        )
            scored.sort(key=lambda x: x["similarity"], reverse=True)
            neighbors = scored[:6]
            self.proximity_graph.graph[doc_id] = neighbors

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

    def _match_term_or_inverted(
        self, clause: QueryClause, target_field: Optional[str]
    ) -> Set[str]:
        matches: Set[str] = set()
        if target_field:
            for tt in self.tokenize(clause.term):
                for doc_id, _ in self.multi_field_index.get_postings(target_field, tt):
                    matches.add(doc_id)
        else:
            for tt in self.tokenize(clause.term):
                if tt in self.inverted_index:
                    matches.update(self.inverted_index[tt])
        return matches

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

    def _filter_clause_candidates(
        self, clauses: List[QueryClause], candidate_ids: Optional[Set[str]]
    ) -> Optional[Set[str]]:
        for clause in clauses:
            clause_matches = self._match_clause_docs(clause)
            if (
                clause.is_required
                or clause.field
                or clause.is_prefix
                or clause.is_fuzzy
            ):
                candidate_ids = (
                    clause_matches
                    if candidate_ids is None
                    else (candidate_ids & clause_matches)
                )
            elif clause.is_prohibited and candidate_ids is not None:
                candidate_ids.difference_update(clause_matches)
        return candidate_ids

    def retrieve_candidates(
        self,
        ctx: QueryContext,
        category: Optional[str] = None,
        max_candidates: int = 600,
    ) -> List[Dict[str, Any]]:
        """Module 2: Hybrid Retrieval & Multi-Field Candidate Pruning."""
        candidate_ids = (
            self.faceted_index.filter(category=category) if category else None
        )
        candidate_ids = self._filter_clause_candidates(ctx.clauses, candidate_ids)

        if candidate_ids is None and ctx.expanded_tokens:
            inv_cands = self._fallback_token_candidates(ctx.expanded_tokens)
            if inv_cands:
                candidate_ids = inv_cands

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
        )
        score = sum(
            self.FIELD_WEIGHTS[f_name] * idf_val
            for f_name, tok_set, text_val in field_checks
            if qt in tok_set or qt in text_val
        )
        if qt in set(doc.get("abstract_tokens", [])):
            score += self.FIELD_WEIGHTS["abstract"] * idf_val
        return score

    def _score_single_doc(
        self, doc: Dict[str, Any], all_query_tokens: List[str]
    ) -> float:
        if not all_query_tokens:
            return 1.0

        field_score = sum(
            self._compute_token_field_score(qt, doc) for qt in all_query_tokens
        )
        bm25_score = self.calculate_bm25_score(all_query_tokens, doc)
        fm_score = self.calculate_fm_index_score(all_query_tokens, doc)
        recency_boost = self.calculate_recency_boost(doc.get("published_date", ""))
        pagerank_boost = 1.0 + 500.0 * self.citation_network.get_score(
            doc.get("id", "")
        )

        return (
            (field_score * 0.35 + bm25_score * 0.35 + fm_score * 0.30)
            * recency_boost
            * pagerank_boost
        )

    def rerank_candidates(
        self,
        ctx: QueryContext,
        target_docs: List[Dict[str, Any]],
        top_k: int = 5,
    ) -> List[Dict[str, Any]]:
        """Module 3: Multi-Stage Ranking & Multi-Field Scoring."""
        scores: List[Dict[str, Any]] = []
        all_query_tokens = [
            tok for t in ctx.expanded_tokens for tok in self.tokenize(t)
        ]

        for doc in target_docs:
            total_score = self._score_single_doc(doc, all_query_tokens)
            if total_score > 0:
                scores.append({"doc": doc, "score": round(total_score, 4)})

        scores.sort(key=lambda x: float(x["score"]), reverse=True)
        return scores[:top_k]

    def format_presentation(
        self,
        ctx: QueryContext,
        ranked_items: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Module 4: Presentation, Snippet & Dynamic Highlighting."""
        highlight_terms = [c.term for c in ctx.clauses]
        if not highlight_terms and ctx.normalized_query:
            highlight_terms = self.tokenize(ctx.normalized_query)

        results = []
        for item in ranked_items:
            doc = item["doc"]
            full_context = f"{doc.get('description', '')} {doc.get('title', '')} {' '.join(doc.get('authors', []))}"
            highlight_snippet = self.highlighter.highlight(
                full_context, highlight_terms
            )

            results.append(
                {
                    "id": doc.get("id"),
                    "title": doc.get("title"),
                    "description": doc.get("description"),
                    "authors": doc.get("authors", []),
                    "tags": doc.get("tags", []),
                    "annotated_keywords": doc.get("annotated_keywords", []),
                    "published_date": doc.get("published_date", ""),
                    "path": doc.get("path"),
                    "highlight": highlight_snippet,
                    "score": item["score"],
                }
            )
        return results

    def log_search_performance(
        self,
        query: str,
        top_k: int,
        category: Optional[str],
        result_count: int,
        profile: Dict[str, Any],
    ) -> None:
        """Appends structured query execution profile to search_perf_log.jsonl."""
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

    def search_with_profile(
        self, query: str, top_k: int = 5, category: Optional[str] = None
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """
        Enterprise Multi-Field & Multi-Stage Hybrid Search with Query Parser & Dynamic Highlighter.
        Measures Wall-clock time, CPU time, and Memory consumption (tracemalloc).
        """
        was_tracing = tracemalloc.is_tracing()
        if not was_tracing:
            tracemalloc.start()
        tracemalloc.reset_peak()
        t0_wall = time.perf_counter()
        t0_cpu = time.process_time()
        start_mem, _ = tracemalloc.get_traced_memory()

        q_tokens = self.tokenize(query) if query else []

        # Phase 0: Semantic Cache Check
        cached_res = self.semantic_cache.get(f"{query}|{category}", q_tokens)
        if cached_res:
            res, prof = cached_res
            prof["cached"] = True
            if not was_tracing:
                tracemalloc.stop()
            return res[:top_k], prof

        t_tokenize_start = time.perf_counter()
        # Serving layer strictly does not build index at query time or during web server startup.
        # Indices must be built in advance via dedicated offline/batch processes (e.g. `make build_vector_db`).

        # Step 1: Query Context Preparation
        ctx = self.prepare_query_context(query)
        t_tokenize_end = time.perf_counter()

        # Step 2: Multi-Field Candidate Retrieval
        t_prune_start = time.perf_counter()
        target_docs = self.retrieve_candidates(
            ctx, category=category, max_candidates=600
        )
        t_prune_end = time.perf_counter()

        # Step 3: Multi-Stage Scoring & Reranking
        t_scoring_start = time.perf_counter()
        ranked_items = self.rerank_candidates(ctx, target_docs, top_k=top_k)
        t_scoring_end = time.perf_counter()

        # Step 4: Presentation & Highlight Generation
        results = self.format_presentation(ctx, ranked_items)
        t_total_end = time.perf_counter()
        t_cpu_end = time.process_time()

        end_mem, peak_mem = tracemalloc.get_traced_memory()
        peak_kb = peak_mem / 1024.0
        delta_kb = (end_mem - start_mem) / 1024.0

        if not was_tracing:
            tracemalloc.stop()

        profile = {
            "tokenize_ms": round((t_tokenize_end - t_tokenize_start) * 1000, 3),
            "candidate_pruning_ms": round((t_prune_end - t_prune_start) * 1000, 3),
            "scoring_ms": round((t_scoring_end - t_scoring_start) * 1000, 3),
            "total_ms": round((t_total_end - t0_wall) * 1000, 3),
            "cpu_ms": round((t_cpu_end - t0_cpu) * 1000, 3),
            "peak_memory_kb": round(peak_kb, 3),
            "memory_delta_kb": round(delta_kb, 3),
            "candidates_evaluated": len(target_docs),
            "total_documents": len(self.documents),
            "clauses_parsed": len(ctx.clauses),
            "intent": ctx.intent,
            "cached": False,
        }

        # Store into Query Semantic Cache
        self.semantic_cache.set(f"{query}|{category}", q_tokens, results, profile)

        # Dump to search_perf_log.jsonl
        self.log_search_performance(
            query=query,
            top_k=top_k,
            category=category,
            result_count=len(results),
            profile=profile,
        )

        return results, profile

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

        graph_context = []
        for kw in query_tokens:
            if kw in self.knowledge_graph.nodes:
                graph_context.append(
                    self.knowledge_graph.get_neighbors(kw, max_depth=1)
                )

        top_related = []
        if results:
            top_id = results[0]["id"]
            top_related = self.proximity_graph.get_neighbors(top_id)

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
