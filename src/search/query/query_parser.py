#!/usr/bin/env python3
"""
Enterprise Multi-Field Query Parser powered by Pure Python Packrat PEG.
Parses field-specific queries (e.g. author:Nakatani, title:malware),
Boolean operators (+/-, AND/OR/NOT), nested parentheses, phrase slop,
prefix (term*), and fuzzy (term~N).
Conforms to DSN-25 Phase 1 specification.
"""

import re
from typing import Any, ClassVar, Dict, List, Optional, Set, cast

from core.structures.peg import (
    Lit,
    NotPred,
    Opt,
    Parser,
    PEGSyntaxError,
    Reg,
    RuleRef,
    Seq,
    ZeroOrMore,
)


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


class EnterpriseQueryParser:
    """
    Parses full-featured query expressions into structured QueryClause objects
    using the Pure Python Packrat PEG Engine.
    """

    ALLOWED_FIELDS: ClassVar[Set[str]] = {
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

    FIELD_ALIAS: ClassVar[Dict[str, str]] = {
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
        self._grammar: Optional[Parser[List[QueryClause]]] = None

    def _get_grammar(self) -> Parser[List[QueryClause]]:
        """Lazily initializes and compiles the PEG query grammar."""
        if self._grammar is None:
            self._grammar = _build_peg_query_grammar(self)
        return self._grammar

    def _parse_fuzzy_plain_term(
        self, term: str, field: Optional[str], is_required: bool, is_prohibited: bool
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

    def _is_reserved_op(self, term: str) -> bool:
        return not term or term.upper() in ("AND", "OR", "NOT")

    def _parse_prefix_plain_term(
        self, term: str, field: Optional[str], is_required: bool, is_prohibited: bool
    ) -> QueryClause:
        return QueryClause(
            field=field,
            term=term[:-1],
            is_required=is_required,
            is_prohibited=is_prohibited,
            is_prefix=True,
        )

    def _is_prefix_term(self, term: str) -> bool:
        return term.endswith("*") and len(term) > 1

    def _is_fuzzy_term(self, term: str) -> bool:
        return "~" in term and not term.startswith("~")

    def _parse_plain_term(
        self, term: str, field: Optional[str], is_required: bool, is_prohibited: bool
    ) -> Optional[QueryClause]:
        if self._is_reserved_op(term):
            return None
        if self._is_prefix_term(term):
            return self._parse_prefix_plain_term(
                term, field, is_required, is_prohibited
            )
        if self._is_fuzzy_term(term):
            return self._parse_fuzzy_plain_term(term, field, is_required, is_prohibited)
        return QueryClause(
            field=field, term=term, is_required=is_required, is_prohibited=is_prohibited
        )

    def _resolve_field(self, field_raw: Optional[str]) -> Optional[str]:
        if not field_raw:
            return None
        field_lower = field_raw.lower()
        field_canon = self.FIELD_ALIAS.get(field_lower, field_lower)
        if (
            field_canon in self.ALLOWED_FIELDS
            or field_canon in self.default_field_weights
        ):
            return field_canon
        return None

    def parse(self, raw_query: str) -> List[QueryClause]:
        """Parses raw query into a list of QueryClause objects using PEG."""
        if not raw_query or not raw_query.strip():
            return []

        grammar = self._get_grammar()
        try:
            return grammar.parse(raw_query.strip())
        except PEGSyntaxError:
            # Resilient fallback: parse individual tokens via regex
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
                is_required=req,
                is_prohibited=proh,
                is_phrase=True,
                phrase_slop=int(slop) if slop else 0,
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


# =========================================================================
# PEG Grammar Construction for Search Queries (Conforming to DSN-25)
# =========================================================================


def _build_peg_query_grammar(
    qp: EnterpriseQueryParser,
) -> Parser[List[QueryClause]]:
    """Constructs the Packrat PEG grammar for full Lucene-style boolean queries."""
    ws = Reg(r"\s+")
    opt_ws = Opt(ws)

    expr_ref = RuleRef("Expr")

    # 1. Atomic Term / Phrase tokens
    def _create_phrase(val: Any) -> QueryClause:
        content = val[1]
        slop_part = val[3]
        slop = int(slop_part[1]) if slop_part else 0
        return QueryClause(term=content.strip(), is_phrase=True, phrase_slop=slop)

    phrase_p = Seq(
        Lit('"'),
        Reg(r'[^"]*'),
        Lit('"'),
        Opt(Seq(Lit("~"), Reg(r"\d+"))),
    ).map(_create_phrase)

    # Keywords not matching standalone as plain terms
    reserved = Reg(r"(?i)\b(AND|OR|NOT)\b")
    term_chars = Reg(r'[^\s"():]+')
    plain_p = Seq(NotPred(reserved), term_chars).map(
        lambda val: qp._parse_plain_term(
            val[1], field=None, is_required=False, is_prohibited=False
        )
    )

    # 2. Field specification: field:term or field:"phrase" or field:(...)
    field_name = Reg(r"[a-zA-Z_]+").map(qp._resolve_field)

    def _apply_field(val: Any) -> QueryClause:
        fld, _, target = val
        if isinstance(target, QueryClause):
            target.field = fld
            return target
        if isinstance(target, list):
            # Target is a nested sub-query list
            for sub in target:
                if sub.field is None:
                    sub.field = fld
            return QueryClause(field=fld, nested_clauses=target)
        return QueryClause(field=fld, term=str(target))

    nested_parens = Seq(Lit("("), opt_ws, expr_ref, opt_ws, Lit(")")).map(
        lambda val: val[2]
    )

    field_target = nested_parens / phrase_p / plain_p
    field_expr = Seq(field_name, Lit(":"), field_target).map(_apply_field)

    # 3. Primary unit
    primary = (
        field_expr
        / phrase_p
        / plain_p
        / nested_parens.map(
            lambda clauses: (
                clauses[0] if len(clauses) == 1 else QueryClause(nested_clauses=clauses)
            )
        )
    )

    # 4. Modifiers (+, -, NOT)
    mod_plus = Lit("+").map(lambda _: "+")
    mod_minus = Lit("-").map(lambda _: "-")
    mod_not = Seq(Reg(r"(?i)\bNOT\b"), ws).map(lambda _: "-")
    mod_p = mod_plus / mod_minus / mod_not

    def _apply_modifier(val: Any) -> Optional[QueryClause]:
        mod, clause = val
        if clause is None:
            return None
        target_clause: QueryClause = cast(QueryClause, clause)
        if mod == "+":
            target_clause.is_required = True
        elif mod == "-":
            target_clause.is_prohibited = True
        return target_clause

    factor = Seq(Opt(mod_p), primary).map(_apply_modifier)

    # 5. Conjunction (AND / implicit whitespace concatenation)
    and_op = Seq(opt_ws, Reg(r"(?i)\bAND\b|&&?"), ws)
    sep_and = and_op / ws

    def _fold_conjunction(val: Any) -> List[QueryClause]:
        first, rest = val
        clauses: List[QueryClause] = [first] if first else []
        for item in rest:
            c = item[1]
            if c:
                clauses.append(c)
        return clauses

    conjunction = Seq(factor, ZeroOrMore(Seq(sep_and, factor))).map(_fold_conjunction)

    # 6. Disjunction (OR)
    or_op = Seq(opt_ws, Reg(r"(?i)\bOR\b|\|\|?"), ws)

    def _fold_disjunction(val: Any) -> List[QueryClause]:
        first_group, rest = val
        first_list = cast(List[QueryClause], first_group)
        if not rest:
            return first_list
        # Create an OR group
        all_groups: List[QueryClause] = []
        if len(first_list) == 1:
            all_groups.append(first_list[0])
        elif first_list:
            all_groups.append(QueryClause(nested_clauses=first_list, logical_op="AND"))
        for item in rest:
            grp = cast(List[QueryClause], item[1])
            if len(grp) == 1:
                all_groups.append(grp[0])
            elif grp:
                all_groups.append(QueryClause(nested_clauses=grp, logical_op="AND"))
        return [QueryClause(nested_clauses=all_groups, logical_op="OR")]

    disjunction = Seq(conjunction, ZeroOrMore(Seq(or_op, conjunction))).map(
        _fold_disjunction
    )

    expr_ref.define(disjunction)

    # Top-level query
    query_grammar = Seq(opt_ws, expr_ref, opt_ws).map(
        lambda val: cast(List[QueryClause], val[1])
    )
    return query_grammar
