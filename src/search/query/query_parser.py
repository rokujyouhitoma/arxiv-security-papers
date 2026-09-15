#!/usr/bin/env python3
"""
Enterprise Multi-Field Query Parser powered by Pure Python Packrat PEG.
Parses field-specific queries (e.g. author:Nakatani, title:malware),
Boolean operators (+/-, AND/OR/NOT), nested parentheses, phrase slop,
prefix (term*), and fuzzy (term~N).
Conforms to DSN-25 Phase 2 Ahead-of-Time PEG specification.
"""

import re
from functools import lru_cache
from typing import Any, ClassVar, Dict, List, Optional, Set, Tuple, cast

from core.structures.peg import PEGSyntaxError

SEARCH_ALLOWED_FIELDS: Set[str] = {
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

SEARCH_FIELD_ALIAS: Dict[str, str] = {
    "authors": "author",
    "tags": "tag",
    "keywords": "keyword",
}


class QueryClause:
    """Represents a single query clause or a nested boolean group."""

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
        nested_clauses: Optional[List["QueryClause"]] = None,
        logical_op: Optional[str] = None,
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
        self.nested_clauses = nested_clauses or []
        self.logical_op = logical_op

    @property
    def is_group(self) -> bool:
        """Returns True if this clause contains nested sub-clauses."""
        return len(self.nested_clauses) > 0

    def _flatten_child(self, child: "QueryClause") -> List["QueryClause"]:
        res: List["QueryClause"] = []
        for leaf in child.flatten():
            req = leaf.is_required or self.is_required
            proh = leaf.is_prohibited or self.is_prohibited
            fld = leaf.field if leaf.field is not None else self.field
            res.append(
                QueryClause(
                    field=fld,
                    term=leaf.term,
                    is_required=req,
                    is_prohibited=proh,
                    is_phrase=leaf.is_phrase,
                    is_prefix=leaf.is_prefix,
                    is_fuzzy=leaf.is_fuzzy,
                    fuzzy_distance=leaf.fuzzy_distance,
                    phrase_slop=leaf.phrase_slop,
                    boost=leaf.boost,
                )
            )
        return res

    def flatten(self) -> List["QueryClause"]:
        """Recursively flattens this clause and its nested sub-clauses with property inheritance."""
        if not self.is_group:
            return [self]
        res: List["QueryClause"] = []
        for child in self.nested_clauses:
            res.extend(self._flatten_child(child))
        return res

    def __repr__(self) -> str:
        if self.is_group:
            return (
                f"QueryClause(group={self.logical_op or 'AND'}, "
                f"children={len(self.nested_clauses)}, "
                f"req={self.is_required}, proh={self.is_prohibited})"
            )
        return (
            f"QueryClause(field={self.field}, term='{self.term}', "
            f"req={self.is_required}, proh={self.is_prohibited}, "
            f"prefix={self.is_prefix}, fuzzy={self.is_fuzzy})"
        )


# =========================================================================
# Standalone Helper Functions for AOT PEG Parser Actions
# =========================================================================


def _resolve_search_field(field_raw: Optional[str]) -> Optional[str]:
    """Resolves and normalizes field alias to canonical field name."""
    if not field_raw:
        return None
    field_lower = field_raw.lower()
    field_canon = SEARCH_FIELD_ALIAS.get(field_lower, field_lower)
    if field_canon in SEARCH_ALLOWED_FIELDS:
        return field_canon
    return None


def _parse_fuzzy_term(
    term: str, field: Optional[str], is_required: bool, is_prohibited: bool
) -> QueryClause:
    parts = term.split("~")
    dist = min(int(parts[1]), 2) if len(parts) > 1 and parts[1].isdigit() else 1
    return QueryClause(
        field=field,
        term=parts[0],
        is_required=is_required,
        is_prohibited=is_prohibited,
        is_fuzzy=True,
        fuzzy_distance=dist,
    )


def _parse_prefix_term(
    term: str, field: Optional[str], is_required: bool, is_prohibited: bool
) -> QueryClause:
    return QueryClause(
        field=field,
        term=term[:-1],
        is_required=is_required,
        is_prohibited=is_prohibited,
        is_prefix=True,
    )


def _is_reserved_query_term(term: str) -> bool:
    return not term or term.upper() in ("AND", "OR", "NOT")


def _is_valid_prefix(term: str) -> bool:
    return term.endswith("*") and len(term) > 1


def _is_valid_fuzzy(term: str) -> bool:
    return "~" in term and not term.startswith("~")


def _parse_search_plain_term(
    term: str,
    field: Optional[str] = None,
    is_required: bool = False,
    is_prohibited: bool = False,
) -> Optional[QueryClause]:
    """Parses a plain term, prefix term, or fuzzy term into a QueryClause."""
    if _is_reserved_query_term(term):
        return None
    if _is_valid_prefix(term):
        return _parse_prefix_term(term, field, is_required, is_prohibited)
    if _is_valid_fuzzy(term):
        return _parse_fuzzy_term(term, field, is_required, is_prohibited)
    return QueryClause(
        field=field, term=term, is_required=is_required, is_prohibited=is_prohibited
    )


def _create_search_phrase(
    content: str,
    slop_val: Optional[int] = None,
    field: Optional[str] = None,
    is_required: bool = False,
    is_prohibited: bool = False,
) -> QueryClause:
    """Creates a phrase query clause with optional slop."""
    return QueryClause(
        field=field,
        term=content.strip(),
        is_phrase=True,
        phrase_slop=slop_val or 0,
        is_required=is_required,
        is_prohibited=is_prohibited,
    )


def _apply_field_to_subclauses(fld: Optional[str], target: List[Any]) -> QueryClause:
    for sub in target:
        if isinstance(sub, QueryClause) and sub.field is None:
            sub.field = fld
    return QueryClause(field=fld, nested_clauses=target)


def _apply_search_field(fld: Optional[str], target: Any) -> QueryClause:
    """Applies resolved field constraint to a QueryClause or nested subclause list."""
    if isinstance(target, QueryClause):
        target.field = fld
        return target
    if isinstance(target, list):
        return _apply_field_to_subclauses(fld, target)
    return QueryClause(field=fld, term=str(target))


def _apply_search_modifier(
    mod: Optional[str], clause: Optional[QueryClause]
) -> Optional[QueryClause]:
    """Applies + or - modifiers to the targeted QueryClause."""
    if clause is None:
        return None
    if mod == "+":
        clause.is_required = True
    elif mod == "-":
        clause.is_prohibited = True
    return clause


def _fold_search_conjunction(
    first: Optional[QueryClause], rest: List[Any]
) -> List[QueryClause]:
    """Folds a sequence of AND-joined or whitespace-separated clauses."""
    clauses: List[QueryClause] = [first] if first else []
    for r in rest:
        if r:
            clauses.append(r)
    return clauses


def _wrap_list_group(items: List[Any]) -> Optional[QueryClause]:
    if not items:
        return None
    if len(items) == 1:
        first = items[0]
        return first if isinstance(first, QueryClause) else None
    return QueryClause(nested_clauses=cast(List[QueryClause], items), logical_op="AND")


def _wrap_clause_group(item: Any) -> Optional[QueryClause]:
    if isinstance(item, QueryClause):
        return item
    if isinstance(item, list):
        return _wrap_list_group(item)
    return None


def _fold_search_disjunction(
    first_list: List[QueryClause], rest: List[Any]
) -> List[QueryClause]:
    """Folds a sequence of OR-joined conjunction groups into a disjunction QueryClause."""
    if not rest:
        return first_list
    all_groups: List[QueryClause] = []
    first_grp = _wrap_clause_group(first_list)
    if first_grp:
        all_groups.append(first_grp)
    for item in rest:
        grp = _wrap_clause_group(item)
        if grp:
            all_groups.append(grp)
    return [QueryClause(nested_clauses=all_groups, logical_op="OR")]


# =========================================================================
# Facade LRU Cache and Global AOT Parser Singleton
# =========================================================================

_GLOBAL_SEARCH_AOT_PARSER: Optional[Any] = None


def _get_global_search_parser() -> Any:
    global _GLOBAL_SEARCH_AOT_PARSER
    if _GLOBAL_SEARCH_AOT_PARSER is None:
        from search.query.generated_search_query_parser import SearchQueryParser

        _GLOBAL_SEARCH_AOT_PARSER = SearchQueryParser()
    return _GLOBAL_SEARCH_AOT_PARSER


@lru_cache(maxsize=1024)
def _cached_aot_search_parse(cleaned: str) -> Tuple[QueryClause, ...]:
    parser = _get_global_search_parser()
    res = parser.parse(cleaned)
    if isinstance(res, list):
        return tuple(cast(List[QueryClause], res))
    if isinstance(res, QueryClause):
        return (res,)
    return ()


def clear_search_query_cache() -> None:
    """Clears the LRU cache for search query parsing."""
    _cached_aot_search_parse.cache_clear()


# =========================================================================
# Enterprise Query Parser Facade
# =========================================================================


class EnterpriseQueryParser:
    """
    Parses full-featured query expressions into structured QueryClause objects
    using the Ahead-of-Time Packrat PEG Compiler (grammars/search_query.peg).
    """

    ALLOWED_FIELDS: ClassVar[Set[str]] = SEARCH_ALLOWED_FIELDS
    FIELD_ALIAS: ClassVar[Dict[str, str]] = SEARCH_FIELD_ALIAS

    def __init__(
        self, default_field_weights: Optional[Dict[str, float]] = None
    ) -> None:
        if default_field_weights is None:
            default_field_weights = {
                "title": 3.0,
                "abstract": 2.0,
                "content": 1.0,
            }
        self.default_field_weights = default_field_weights
        self._parser: Optional[Any] = None

    def _get_parser(self) -> Any:
        """Lazily imports and instantiates the AOT-compiled SearchQueryParser."""
        return _get_global_search_parser()

    def _resolve_field(self, field_raw: Optional[str]) -> Optional[str]:
        return _resolve_search_field(field_raw)

    def _parse_plain_term(
        self, term: str, field: Optional[str], is_required: bool, is_prohibited: bool
    ) -> Optional[QueryClause]:
        return _parse_search_plain_term(term, field, is_required, is_prohibited)

    @staticmethod
    def _coerce_parse_result(res: Any) -> List[QueryClause]:
        if isinstance(res, list):
            return cast(List[QueryClause], res)
        if isinstance(res, QueryClause):
            return [res]
        return []

    def parse(self, raw_query: str) -> List[QueryClause]:
        """Parses raw query into a list of QueryClause objects using AOT PEG with LRU caching."""
        cleaned = (raw_query or "").strip()
        if not cleaned:
            return []

        try:
            return list(_cached_aot_search_parse(cleaned))
        except PEGSyntaxError:
            return self._fallback_regex_parse(raw_query)

    def _parse_fallback_match(self, m: Any) -> Optional[QueryClause]:
        mod, fld_raw, phr, slop, plain = m.groups()
        req = mod == "+"
        proh = mod == "-"
        fld = self._resolve_field(fld_raw)
        if phr is not None:
            return QueryClause(
                field=fld,
                term=phr.strip(),
                is_phrase=True,
                phrase_slop=int(slop) if slop else 0,
                is_required=req,
                is_prohibited=proh,
            )
        if plain is not None:
            return self._parse_plain_term(plain.strip(), fld, req, proh)
        return None

    def _fallback_regex_parse(self, raw_query: str) -> List[QueryClause]:
        """Fallback parser for malformed unclosed parenthesis queries."""
        pattern = re.compile(
            r"([+\-])?" r"(?:([a-zA-Z_]+):)?" r'(?:"([^"]+)"(?:~(\d+))?|([^\s"()]+))'
        )
        clauses: List[QueryClause] = []
        for m in pattern.finditer(raw_query):
            c = self._parse_fallback_match(m)
            if c is not None:
                clauses.append(c)
        return clauses

    @staticmethod
    def _is_bool_filtered(clauses: List[QueryClause]) -> bool:
        for c in clauses:
            if c.is_required or c.is_prohibited:
                return True
        return False

    @staticmethod
    def _resolve_clause_intent(clauses: List[QueryClause]) -> Optional[str]:
        if EnterpriseQueryParser._is_bool_filtered(clauses):
            return "boolean_filtered"
        for c in clauses:
            if c.is_phrase:
                return "phrase_match"
        return None

    @staticmethod
    def _resolve_intent(
        target_fields: Set[str], clauses: List[QueryClause], raw_clean: str
    ) -> str:
        if target_fields:
            return "field_specific"
        clause_intent = EnterpriseQueryParser._resolve_clause_intent(clauses)
        if clause_intent:
            return clause_intent
        if len(raw_clean.split()) > 5:
            return "natural_language_qa"
        return "general"

    @staticmethod
    def _extract_clause_terms(clauses: List[QueryClause]) -> List[str]:
        res: List[str] = []
        for c in clauses:
            for fc in c.flatten():
                if fc.term:
                    res.append(fc.term.lower())
        return res

    def _get_expanded_tokens(
        self, raw_clean: str, clauses: List[QueryClause], expander: Optional[Any]
    ) -> List[str]:
        if expander and hasattr(expander, "expand_query"):
            return list(expander.expand_query(raw_clean))
        return self._extract_clause_terms(clauses)

    def _extract_target_fields(self, clauses: List[QueryClause]) -> Set[str]:
        flat = [fc for c in clauses for fc in c.flatten()]
        return {c.field for c in flat if c.field is not None}

    def create_context(
        self,
        raw_query: str,
        expander: Optional[Any] = None,
    ) -> "QueryContext":
        """Creates a fully resolved QueryContext from raw query string."""
        raw_clean = (raw_query or "").strip()
        clauses = self.parse(raw_clean)
        target_fields = self._extract_target_fields(clauses)
        expanded_tokens = self._get_expanded_tokens(raw_clean, clauses, expander)
        flat_clauses = [fc for c in clauses for fc in c.flatten()]
        intent = self._resolve_intent(target_fields, flat_clauses, raw_clean)
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
    def original_query(self) -> str:
        return self.raw_query

    @property
    def original_tokens(self) -> List[str]:
        return self.expanded_tokens

    @property
    def has_field_constraints(self) -> bool:
        """Returns True if query has explicit field targeting (e.g. title:xxx)."""
        return len(self.target_fields) > 0

    @property
    def required_clauses(self) -> List[QueryClause]:
        """Returns clauses marked with + / required."""
        flat = [fc for c in self.clauses for fc in c.flatten()]
        return [c for c in flat if c.is_required]

    @property
    def prohibited_clauses(self) -> List[QueryClause]:
        """Returns clauses marked with - / prohibited."""
        flat = [fc for c in self.clauses for fc in c.flatten()]
        return [c for c in flat if c.is_prohibited]

    def __repr__(self) -> str:
        return (
            f"QueryContext(raw='{self.raw_query}', clauses={len(self.clauses)}, "
            f"tokens={len(self.expanded_tokens)}, fields={self.target_fields}, intent='{self.intent}')"
        )


# Alias for backward compatibility and Issue #303 specification
QueryParser = EnterpriseQueryParser
