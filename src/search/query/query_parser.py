#!/usr/bin/env python3
"""
Enterprise Multi-Field Query Parser.
Parses field-specific queries (e.g. author:Nakatani, title:malware),
Boolean operators (+/-, AND/OR/NOT), Phrase slop, Prefix (term*), and Fuzzy (term~N).
"""

import re
from typing import Any, Dict, List, Optional, Set


class QueryClause:
    """Represents a single query clause."""

    def __init__(
        self,
        field: Optional[str] = None,
        term: str = "",
        is_required: bool = False,
        is_prohibited: bool = False,
        is_phrase: bool = False,
        is_prefix: bool = False,
        is_fuzzy: bool = False,
        fuzzy_distance: int = 1,
        phrase_slop: int = 0,
        boost: float = 1.0,
    ) -> None:
        self.field = field  # None means search all default fields
        self.term = term
        self.is_required = is_required
        self.is_prohibited = is_prohibited
        self.is_phrase = is_phrase
        self.is_prefix = is_prefix
        self.is_fuzzy = is_fuzzy
        self.fuzzy_distance = fuzzy_distance
        self.phrase_slop = phrase_slop
        self.boost = boost

    def __repr__(self) -> str:
        return (
            f"QueryClause(field={self.field}, term='{self.term}', "
            f"req={self.is_required}, proh={self.is_prohibited}, "
            f"prefix={self.is_prefix}, fuzzy={self.is_fuzzy})"
        )


class EnterpriseQueryParser:
    """
    Parses full-featured query expressions into structured QueryClause objects.
    """

    ALLOWED_FIELDS = {
        "author",
        "authors",
        "title",
        "abstract",
        "content",
        "tag",
        "tags",
        "keyword",
        "keywords",
        "id",
    }

    FIELD_ALIAS = {
        "authors": "author",
        "tags": "tag",
        "keywords": "keyword",
    }

    def __init__(
        self,
        default_field_weights: Optional[Dict[str, float]] = None,
    ) -> None:
        if default_field_weights is None:
            default_field_weights = {
                "title": 4.0,
                "author": 3.5,
                "keywords": 3.0,
                "abstract": 2.0,
                "content": 1.0,
            }
        self.default_field_weights = default_field_weights

    def parse(self, raw_query: str) -> List[QueryClause]:
        """
        Parses raw query into a list of QueryClause objects.
        """
        if not raw_query or not raw_query.strip():
            return []

        # Tokenize with regex handling quotes, modifiers, and field prefixes
        # Matches: [+/-]? [field:]? ("phrase"~N | term~N | term* | term)
        pattern = re.compile(
            r"([+\-])?" r"(?:([a-zA-Z_]+):)?" r'(?:"([^"]+)"(?:~(\d+))?|([^\s"]+))'
        )

        clauses: List[QueryClause] = []
        for m in pattern.finditer(raw_query):
            modifier = m.group(1) or ""
            field_raw = m.group(2)
            phrase_content = m.group(3)
            phrase_slop_str = m.group(4)
            plain_term = m.group(5)

            is_required = modifier == "+"
            is_prohibited = modifier == "-"

            field: Optional[str] = None
            if field_raw:
                field_lower = field_raw.lower()
                field_canon = self.FIELD_ALIAS.get(field_lower, field_lower)
                if (
                    field_canon in self.ALLOWED_FIELDS
                    or field_canon in self.default_field_weights
                ):
                    field = field_canon

            if phrase_content is not None:
                slop = int(phrase_slop_str) if phrase_slop_str else 0
                clauses.append(
                    QueryClause(
                        field=field,
                        term=phrase_content.strip(),
                        is_required=is_required,
                        is_prohibited=is_prohibited,
                        is_phrase=True,
                        phrase_slop=slop,
                    )
                )
            elif plain_term is not None:
                term = plain_term.strip()
                if not term:
                    continue

                # Check for Boolean keywords
                if term.upper() == "AND" or term.upper() == "OR":
                    continue
                if term.upper() == "NOT":
                    continue

                # Check for Wildcard/Prefix: term*
                if term.endswith("*") and len(term) > 1:
                    clauses.append(
                        QueryClause(
                            field=field,
                            term=term[:-1],
                            is_required=is_required,
                            is_prohibited=is_prohibited,
                            is_prefix=True,
                        )
                    )
                # Check for Fuzzy: term~1 or term~
                elif "~" in term and not term.startswith("~"):
                    parts = term.split("~")
                    fuzzy_base = parts[0]
                    dist = 1
                    if len(parts) > 1 and parts[1].isdigit():
                        dist = min(int(parts[1]), 2)
                    clauses.append(
                        QueryClause(
                            field=field,
                            term=fuzzy_base,
                            is_required=is_required,
                            is_prohibited=is_prohibited,
                            is_fuzzy=True,
                            fuzzy_distance=dist,
                        )
                    )
                else:
                    clauses.append(
                        QueryClause(
                            field=field,
                            term=term,
                            is_required=is_required,
                            is_prohibited=is_prohibited,
                        )
                    )

        return clauses

    def create_context(
        self,
        raw_query: str,
        expander: Optional[Any] = None,
    ) -> "QueryContext":
        """Creates a fully resolved QueryContext from raw query string."""
        raw_clean = (raw_query or "").strip()
        clauses = self.parse(raw_clean)
        target_fields: Set[str] = {c.field for c in clauses if c.field is not None}

        # Expand synonyms if expander is provided
        expanded_tokens: List[str] = []
        if expander and hasattr(expander, "expand_query"):
            expanded_tokens = expander.expand_query(raw_clean)
        else:
            expanded_tokens = [c.term.lower() for c in clauses if c.term]

        # Intent classification heuristics
        intent = "general"
        if target_fields:
            intent = "field_specific"
        elif any(c.is_required or c.is_prohibited for c in clauses):
            intent = "boolean_filtered"
        elif any(c.is_phrase for c in clauses):
            intent = "phrase_match"
        elif len(raw_clean.split()) > 5:
            intent = "natural_language_qa"

        is_hybrid = not (target_fields and "content" not in target_fields)

        return QueryContext(
            raw_query=raw_clean,
            normalized_query=raw_clean.lower(),
            clauses=clauses,
            expanded_tokens=expanded_tokens,
            target_fields=target_fields,
            intent=intent,
            is_hybrid_eligible=is_hybrid,
        )


class QueryContext:
    """Unified query context carrying parsed clauses, synonyms, target fields, and search intent."""

    def __init__(
        self,
        raw_query: str,
        normalized_query: str,
        clauses: List[QueryClause],
        expanded_tokens: List[str],
        target_fields: Set[str],
        intent: str = "general",
        is_hybrid_eligible: bool = True,
    ) -> None:
        self.raw_query = raw_query
        self.normalized_query = normalized_query
        self.clauses = clauses
        self.expanded_tokens = expanded_tokens
        self.target_fields = target_fields
        self.intent = intent
        self.is_hybrid_eligible = is_hybrid_eligible

    @property
    def has_field_constraints(self) -> bool:
        """Returns True if query has explicit field targeting (e.g. title:xxx)."""
        return len(self.target_fields) > 0

    @property
    def required_clauses(self) -> List[QueryClause]:
        """Returns clauses marked with + / required."""
        return [c for c in self.clauses if c.is_required]

    @property
    def prohibited_clauses(self) -> List[QueryClause]:
        """Returns clauses marked with - / prohibited."""
        return [c for c in self.clauses if c.is_prohibited]

    def __repr__(self) -> str:
        return (
            f"QueryContext(raw='{self.raw_query}', clauses={len(self.clauses)}, "
            f"tokens={len(self.expanded_tokens)}, fields={self.target_fields}, intent='{self.intent}')"
        )
