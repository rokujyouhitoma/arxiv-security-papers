#!/usr/bin/env python3
"""
Core Search and Scoring Subpackage.
"""

from .collector import ScoreDoc, TopDocs, TopDocsCollector
from .query import (
    BooleanClause,
    BooleanQuery,
    FuzzyQuery,
    PhraseQuery,
    PrefixQuery,
    Query,
    TermQuery,
)
from .similarity import BM25Similarity, Similarity

__all__ = [
    "BM25Similarity",
    "BooleanClause",
    "BooleanQuery",
    "FuzzyQuery",
    "PhraseQuery",
    "PrefixQuery",
    "Query",
    "ScoreDoc",
    "Similarity",
    "TermQuery",
    "TopDocs",
    "TopDocsCollector",
]
