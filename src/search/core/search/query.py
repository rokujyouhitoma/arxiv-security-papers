#!/usr/bin/env python3
"""
Lucene-style Query Abstract Syntax Tree (AST) Models.
"""

from typing import List, Optional


class Query:
    """Base abstract Query."""

    pass


class TermQuery(Query):
    """Matches exact single term in a specific field."""

    def __init__(self, field: str, term: str, boost: float = 1.0) -> None:
        self.field = field
        self.term = term
        self.boost = boost

    def __repr__(self) -> str:
        return (
            f"TermQuery(field='{self.field}', term='{self.term}', boost={self.boost})"
        )


class BooleanClause:
    """Clause in a BooleanQuery with occur requirement (+ / - / should)."""

    def __init__(
        self, query: Query, is_required: bool = False, is_prohibited: bool = False
    ) -> None:
        self.query = query
        self.is_required = is_required
        self.is_prohibited = is_prohibited

    def __repr__(self) -> str:
        return f"BooleanClause(req={self.is_required}, proh={self.is_prohibited}, q={self.query})"


class BooleanQuery(Query):
    """Combines multiple queries with Boolean logic (+, -, SHOULD)."""

    def __init__(self, clauses: Optional[List[BooleanClause]] = None) -> None:
        self.clauses = clauses or []

    def add(
        self, query: Query, is_required: bool = False, is_prohibited: bool = False
    ) -> None:
        self.clauses.append(BooleanClause(query, is_required, is_prohibited))

    def __repr__(self) -> str:
        return f"BooleanQuery(clauses={len(self.clauses)})"


class PhraseQuery(Query):
    """Matches sequence of terms with optional slop distance."""

    def __init__(self, field: str, terms: List[str], slop: int = 0) -> None:
        self.field = field
        self.terms = terms
        self.slop = slop


class PrefixQuery(Query):
    """Matches terms starting with a given prefix."""

    def __init__(self, field: str, prefix: str) -> None:
        self.field = field
        self.prefix = prefix


class FuzzyQuery(Query):
    """Matches terms within Levenshtein edit distance."""

    def __init__(self, field: str, term: str, max_edits: int = 1) -> None:
        self.field = field
        self.term = term
        self.max_edits = max_edits
