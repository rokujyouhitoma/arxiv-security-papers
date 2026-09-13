#!/usr/bin/env python3
"""
src/database/storage/fts5_storage.py

Pure-Python FTS5 (Full-Text Search 5) Storage Engine.
Conforms to SQLite FTS5 specification (sqlite.org/fts5.html),
Okapi BM25 ranking algorithm, and zero-external-dependency rule.
"""

from __future__ import annotations

import json
import math
import os
import re
from typing import Any, Dict, List, Optional, Set, Tuple


class Fts5Tokenizer:
    """Standard tokenizer for FTS5 (unicode61 & ascii token parsing)."""

    def __init__(self, mode: str = "unicode61") -> None:
        self.mode = mode.lower()

    def tokenize(self, text: str) -> List[str]:
        """Extracts normalized tokens from input text in linear O(N) time."""
        if not text:
            return []
        lower_text = text.lower()
        return re.findall(r"\b\w+\b", lower_text)

    def tokenize_query(self, text: str) -> List[str]:
        """Extracts query tokens preserving trailing wildcard *."""
        if not text:
            return []
        return [t for t in re.findall(r"\b\w+\*?", text.lower()) if t]


def _compute_idf(n_q: int, n_docs: int) -> float:
    """Computes standard smoothed BM25 IDF."""
    numerator = n_docs - n_q + 0.5
    denominator = n_q + 0.5
    return math.log(1.0 + max(0.0, numerator / denominator))


def _compute_term_bm25(
    tf: int, doc_len: int, avg_dl: float, idf: float, k1: float = 1.2, b: float = 0.75
) -> float:
    """Computes BM25 contribution for a single query term."""
    denom_len = 1.0 - b + b * (doc_len / avg_dl if avg_dl > 0 else 1.0)
    denom = tf + k1 * denom_len
    if denom == 0:
        return 0.0
    return idf * (tf * (k1 + 1.0)) / denom


class Fts5StorageEngine:
    """
    Pluggable Full-Text Search 5 Storage Engine.
    Provides inverted indexing, posting lists, and Okapi BM25 ranking.
    """

    def __init__(
        self,
        file_path: Optional[str] = None,
        columns: Optional[List[str]] = None,
        tokenize: str = "unicode61",
        **kwargs: Any,
    ) -> None:
        self.file_path = os.path.abspath(file_path) if file_path else None
        self.columns = list(columns) if columns else ["content"]
        self.tokenizer = Fts5Tokenizer(tokenize)
        self.records: List[Dict[str, Any]] = []
        # Inverted index: term -> {doc_idx: {column_name: tf}}
        self.index: Dict[str, Dict[int, Dict[str, int]]] = {}
        # Document lengths: doc_idx -> total tokens across indexed columns
        self.doc_lens: Dict[int, int] = {}
        self._load_if_exists()

    @property
    def metadata(self) -> List[Dict[str, Any]]:
        """Returns the active records for scanning and reflection."""
        return self.records

    @property
    def schema(self) -> Dict[str, str]:
        """Exposes schema definitions for the virtual table."""
        return {col: "TEXT" for col in self.columns}

    def fieldnames(self) -> List[str]:
        """Returns column names."""
        return list(self.columns)

    def _ensure_parent_dir(self) -> None:
        if self.file_path:
            parent = os.path.dirname(self.file_path)
            if parent:
                os.makedirs(parent, exist_ok=True)

    def _parse_loaded_items(self, data: Any) -> None:
        if isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    self.append(item)

    def _load_if_exists(self) -> None:
        if not self.file_path or not os.path.exists(self.file_path):
            return
        try:
            with open(self.file_path, "r", encoding="utf-8") as f:
                self._parse_loaded_items(json.load(f))
        except (OSError, json.JSONDecodeError):
            pass

    def save(self) -> None:
        """Flushes in-memory records to backing file if configured."""
        if not self.file_path:
            return
        self._ensure_parent_dir()
        tmp_file = f"{self.file_path}.tmp"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(self.records, f, ensure_ascii=False, indent=2)
        os.replace(tmp_file, self.file_path)

    def _add_token_posting(self, tok: str, doc_idx: int, col: str) -> None:
        if tok not in self.index:
            self.index[tok] = {}
        if doc_idx not in self.index[tok]:
            self.index[tok][doc_idx] = {}
        col_map = self.index[tok][doc_idx]
        col_map[col] = col_map.get(col, 0) + 1

    def _index_col_tokens(self, doc_idx: int, col: str, val: Any) -> int:
        tokens = self.tokenizer.tokenize(str(val) if val is not None else "")
        for tok in tokens:
            self._add_token_posting(tok, doc_idx, col)
        return len(tokens)

    def _index_document(self, doc_idx: int, record: Dict[str, Any]) -> None:
        """Tokenizes and indexes all columns for a given document."""
        total_len = sum(
            self._index_col_tokens(doc_idx, col, record.get(col, ""))
            for col in self.columns
        )
        self.doc_lens[doc_idx] = total_len

    def append(self, record: Dict[str, Any]) -> int:
        """Appends a new document and updates the inverted index."""
        doc_idx = len(self.records)
        clean_row = {col: record.get(col) for col in self.columns}
        for k, v in record.items():
            if k not in clean_row:
                clean_row[k] = v
        self.records.append(clean_row)
        self._index_document(doc_idx, clean_row)
        self.save()
        return doc_idx

    def upsert(self, record: Dict[str, Any]) -> None:
        """Upserts a record or appends if new."""
        self.append(record)

    def _rebuild_index(self) -> None:
        """Rebuilds the entire inverted index from active records."""
        self.index.clear()
        self.doc_lens.clear()
        for idx, rec in enumerate(self.records):
            self._index_document(idx, rec)

    def delete_indices(self, indices: List[int]) -> None:
        """Deletes documents at specified indices and re-indexes."""
        del_set = set(indices)
        self.records = [r for i, r in enumerate(self.records) if i not in del_set]
        self._rebuild_index()
        self.save()

    def _get_avg_doc_len(self) -> float:
        if not self.doc_lens:
            return 0.0
        return sum(self.doc_lens.values()) / float(len(self.doc_lens))

    def _term_freq(
        self, term: str, doc_idx: int, target_col: Optional[str] = None
    ) -> int:
        """Calculates term frequency within target column or across all columns."""
        postings = self.index.get(term, {})
        doc_entry = postings.get(doc_idx)
        if not doc_entry:
            return 0
        if target_col:
            return doc_entry.get(target_col, 0)
        return sum(doc_entry.values())

    def _matching_terms_for_query(self, query_term: str) -> List[str]:
        """Supports exact match or prefix wildcard query (e.g. 'secur*')."""
        if query_term.endswith("*"):
            prefix = query_term[:-1].lower()
            return [t for t in self.index if t.startswith(prefix)]
        term = query_term.lower()
        return [term] if term in self.index else []

    def _docs_for_token(
        self, q_term: str, target_col: Optional[str] = None
    ) -> Set[int]:
        """Finds all doc indices containing the query token."""
        matching_terms = self._matching_terms_for_query(q_term)
        docs: Set[int] = set()
        for t in matching_terms:
            for doc_idx, col_map in self.index.get(t, {}).items():
                if target_col is None or target_col in col_map:
                    docs.add(doc_idx)
        return docs

    def _candidate_docs(
        self, query_tokens: List[str], target_col: Optional[str] = None
    ) -> Set[int]:
        """Finds candidate documents matching all query tokens (AND semantics)."""
        if not query_tokens:
            return set()
        first_docs = self._docs_for_token(query_tokens[0], target_col)
        candidates = set(first_docs)
        for tok in query_tokens[1:]:
            tok_docs = self._docs_for_token(tok, target_col)
            candidates.intersection_update(tok_docs)
        return candidates

    def _calc_doc_bm25(
        self,
        doc_idx: int,
        query_tokens: List[str],
        avg_dl: float,
        target_col: Optional[str] = None,
    ) -> float:
        """Computes BM25 score for a single candidate document."""
        n_docs = len(self.records)
        score = 0.0
        doc_len = self.doc_lens.get(doc_idx, 0)
        for tok in query_tokens:
            m_terms = self._matching_terms_for_query(tok)
            doc_tf = sum(self._term_freq(t, doc_idx, target_col) for t in m_terms)
            if doc_tf > 0:
                n_q = len(self._docs_for_token(tok, target_col))
                idf = _compute_idf(n_q, n_docs)
                score += _compute_term_bm25(doc_tf, doc_len, avg_dl, idf)
        return score

    def match(
        self, query: str, target_column: Optional[str] = None
    ) -> List[Tuple[int, float]]:
        """
        Executes full-text search query and returns list of (doc_idx, bm25_score)
        sorted by relevance descending.
        """
        q_tokens = self.tokenizer.tokenize_query(query)
        if not q_tokens:
            return []
        candidates = self._candidate_docs(q_tokens, target_column)
        if not candidates:
            return []
        avg_dl = self._get_avg_doc_len()
        results: List[Tuple[int, float]] = []
        for doc_idx in candidates:
            score = self._calc_doc_bm25(doc_idx, q_tokens, avg_dl, target_column)
            results.append((doc_idx, round(score, 4)))
        results.sort(key=lambda x: x[1], reverse=True)
        return results

    def bm25(
        self, doc_idx: int, query: str, target_column: Optional[str] = None
    ) -> float:
        """Returns the BM25 score for a specific document index and query."""
        q_tokens = self.tokenizer.tokenize_query(query)
        if not q_tokens or doc_idx >= len(self.records):
            return 0.0
        avg_dl = self._get_avg_doc_len()
        return round(self._calc_doc_bm25(doc_idx, q_tokens, avg_dl, target_column), 4)
