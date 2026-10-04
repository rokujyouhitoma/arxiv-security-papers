"""Scope Sets Hygienic Macro System for ILISP (R7RS syntax-rules).

This module implements Matthew Flatt's "Binding as Sets of Scopes" (POPL 2016)
algorithm to provide hygienic macro expansion without variable capture.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Set, Tuple

from ilisp.types import (
    Cons,
    SourceLocation,
    Symbol,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
)


class Scope:
    """A distinct scope token in the Scope Sets model."""

    _counter: int = 0

    def __init__(self, name: str = "s") -> None:
        Scope._counter += 1
        self.id: int = Scope._counter
        self.name: str = name

    def __repr__(self) -> str:
        return f"<Scope {self.name}#{self.id}>"

    def __hash__(self) -> int:
        return hash(self.id)

    def __eq__(self, other: Any) -> bool:
        if isinstance(other, Scope):
            return self.id == other.id
        return False


class Syntax:
    """A Syntax Object encapsulating a datum and its set of scopes."""

    __slots__ = ("datum", "scopes", "loc")

    def __init__(
        self,
        datum: Any,
        scopes: Optional[Set[Scope]] = None,
        loc: Optional[SourceLocation] = None,
    ) -> None:
        self.datum: Any = datum
        self.scopes: Set[Scope] = set(scopes) if scopes else set()
        self.loc: Optional[SourceLocation] = loc

    def add_scope(self, scope: Scope) -> Syntax:
        """Return a new Syntax with the added scope (recursive for pairs/vectors)."""
        new_scopes = set(self.scopes)
        new_scopes.add(scope)
        if isinstance(self.datum, Cons):
            new_car = (
                self.datum.car.add_scope(scope)
                if isinstance(self.datum.car, Syntax)
                else self.datum.car
            )
            new_cdr = (
                self.datum.cdr.add_scope(scope)
                if isinstance(self.datum.cdr, Syntax)
                else self.datum.cdr
            )
            return Syntax(Cons(new_car, new_cdr), new_scopes, self.loc)
        elif isinstance(self.datum, Vector):
            new_elems = [
                e.add_scope(scope) if isinstance(e, Syntax) else e
                for e in self.datum.elements
            ]
            return Syntax(Vector(new_elems), new_scopes, self.loc)
        return Syntax(self.datum, new_scopes, self.loc)

    def __repr__(self) -> str:
        if isinstance(self.datum, Symbol):
            sc_str = ",".join(
                str(s.id) for s in sorted(self.scopes, key=lambda s: s.id)
            )
            return f"Syntax({self.datum.name}#{sc_str})"
        return f"Syntax({self.datum!r})"


def datum_to_syntax(
    datum: Any,
    scopes: Optional[Set[Scope]] = None,
    loc: Optional[SourceLocation] = None,
) -> Any:
    """Recursively wrap an S-expression into Syntax objects with initial scopes."""
    sc = set(scopes) if scopes else set()
    if isinstance(datum, Symbol):
        return Syntax(datum, sc, loc)
    elif isinstance(datum, Cons):
        new_car = datum_to_syntax(datum.car, sc, loc)
        new_cdr = datum_to_syntax(datum.cdr, sc, loc)
        return Syntax(Cons(new_car, new_cdr), sc, loc)
    elif isinstance(datum, Vector):
        new_elems = [datum_to_syntax(e, sc, loc) for e in datum.elements]
        return Syntax(Vector(new_elems), sc, loc)
    elif isinstance(datum, Syntax):
        return datum
    else:
        # Self-evaluating literals
        return Syntax(datum, sc, loc)


def syntax_to_datum(stx: Any, use_scope: Optional[Scope] = None) -> Any:
    """Convert a Syntax object back to a standard Lisp S-expression.

    If use_scope is provided, symbols bearing use_scope that were introduced
    by the macro definition are renamed hygienically to avoid capturing caller variables.
    """
    if isinstance(stx, Syntax):
        d = stx.datum
        if isinstance(d, Symbol):
            # If the symbol has the macro use-scope, rename it hygienically
            if use_scope is not None and use_scope in stx.scopes:
                core_forms = {
                    "quote",
                    "lambda",
                    "if",
                    "set!",
                    "begin",
                    "define",
                    "let",
                    "let*",
                    "cond",
                    "case",
                    "and",
                    "or",
                    "when",
                    "unless",
                    "call/cc",
                    "call-with-current-continuation",
                    "values",
                    "call-with-values",
                    "raise",
                    "raise-continuable",
                    "with-exception-handler",
                    "guard",
                    "error",
                    "error-object?",
                    "error-object-message",
                    "error-object-irritants",
                    "read-error?",
                    "file-error?",
                    "cons",
                    "car",
                    "cdr",
                    "caar",
                    "cadr",
                    "cdar",
                    "cddr",
                    "null?",
                    "pair?",
                    "list",
                    "length",
                    "append",
                    "reverse",
                    "map",
                    "filter",
                    "fold-left",
                    "for-each",
                    "member",
                    "memq",
                    "memv",
                    "assoc",
                    "assq",
                    "vector",
                    "vector?",
                    "make-vector",
                    "vector-ref",
                    "vector-set!",
                    "vector-length",
                    "vector->list",
                    "list->vector",
                    "symbol?",
                    "symbol->string",
                    "string?",
                    "string-append",
                    "string=?",
                    "eq?",
                    "eqv?",
                    "equal?",
                    "boolean?",
                    "not",
                    "+",
                    "-",
                    "*",
                    "/",
                    "quotient",
                    "remainder",
                    "modulo",
                    "=",
                    "<",
                    ">",
                    "<=",
                    ">=",
                    "display",
                    "write",
                    "newline",
                    "read-char",
                    "eof-object?",
                    "load",
                }
                if d.name in core_forms:
                    return d
                return Symbol.intern(f"{d.name}__hyg_{use_scope.id}")
            return d
        elif isinstance(d, Cons):
            return Cons(
                syntax_to_datum(d.car, use_scope),
                syntax_to_datum(d.cdr, use_scope),
            )
        elif isinstance(d, Vector):
            return Vector([syntax_to_datum(e, use_scope) for e in d.elements])
        return d
    elif isinstance(stx, Cons):
        return Cons(
            syntax_to_datum(stx.car, use_scope),
            syntax_to_datum(stx.cdr, use_scope),
        )
    elif isinstance(stx, Vector):
        return Vector([syntax_to_datum(e, use_scope) for e in stx.elements])
    return stx


class PatternBinding:
    """Holds matched syntax elements for a pattern variable."""

    def __init__(self, depth: int, value: Any) -> None:
        self.depth: int = (
            depth  # 0 for single syntax, 1 for list, 2 for nested list, etc.
        )
        self.value: Any = value


class SyntaxRulesTransformer:
    """A hygienic syntax-rules macro transformer adhering to R7RS-small."""

    def __init__(
        self,
        name: str,
        literals: List[str],
        rules: List[Tuple[Any, Any]],  # List of (pattern, template) S-expressions
    ) -> None:
        self.name: str = name
        self.literals: Set[str] = set(literals)
        self.rules: List[Tuple[Any, Any]] = rules
        self.def_scope: Scope = Scope(f"def_{name}")

    def transform(self, input_form: Any) -> Any:
        """Apply the first matching syntax-rule to the input form and return expanded S-expression."""
        use_scope = Scope(f"use_{self.name}")

        # Wrap input into syntax with caller scopes
        caller_scope = Scope("caller")
        input_stx = datum_to_syntax(input_form, {caller_scope})

        # Input form is usually (macro-name arg ...)
        # Strip macro name from matching pattern/input
        if not (isinstance(input_stx, Syntax) and isinstance(input_stx.datum, Cons)):
            raise SyntaxError(f"Invalid macro call to {self.name}: {input_form!r}")

        input_cdr = input_stx.datum.cdr

        for pat, tmpl in self.rules:
            # Pattern format is (macro-name pat-args ...)
            if not (is_pair(pat) and isinstance(car(pat), Symbol)):
                raise SyntaxError(f"Malformed syntax-rules pattern: {pat!r}")
            pat_cdr = cdr(pat)

            bindings: Dict[str, PatternBinding] = {}
            if self._match_pattern(pat_cdr, input_cdr, bindings):
                # Pattern matched! Expand template
                expanded_stx = self._expand_template(tmpl, bindings, use_scope)
                # Convert back to standard S-expression
                return syntax_to_datum(expanded_stx, use_scope)

        raise SyntaxError(
            f"No matching rule in syntax-rules for macro '{self.name}': {input_form!r}"
        )

    def _match_pattern(
        self,
        pat: Any,
        input_stx: Any,
        bindings: Dict[str, PatternBinding],
    ) -> bool:
        """Match pat against input_stx and populate bindings. Returns True on success."""
        # Unpack Syntax if needed
        unwrapped_input = (
            input_stx.datum if isinstance(input_stx, Syntax) else input_stx
        )

        # 1. Ellipsis pattern in list
        if is_pair(pat):
            pat_car = car(pat)
            pat_cdr = cdr(pat)

            # Check if followed by ellipsis '...'
            if (
                is_pair(pat_cdr)
                and isinstance(car(pat_cdr), Symbol)
                and car(pat_cdr).name == "..."
            ):
                rest_pat = cdr(pat_cdr)
                # Matches 0 or more occurrences of pat_car, followed by rest_pat
                return self._match_ellipsis(pat_car, rest_pat, input_stx, bindings)

            # Normal pair matching
            if not is_pair(unwrapped_input):
                return False
            if not self._match_pattern(pat_car, unwrapped_input.car, bindings):
                return False
            return self._match_pattern(pat_cdr, unwrapped_input.cdr, bindings)

        # 2. Empty list
        if is_null(pat):
            return is_null(unwrapped_input)

        # 3. Symbol pattern: literal or pattern variable
        if isinstance(pat, Symbol):
            if pat.name in self.literals:
                # Must match literal symbol exactly
                if isinstance(unwrapped_input, Symbol):
                    return unwrapped_input.name == pat.name
                return False
            elif pat.name == "_":
                # Wildcard: matches anything without binding
                return True
            else:
                # Pattern variable!
                bindings[pat.name] = PatternBinding(depth=0, value=input_stx)
                return True

        # 4. Constant literal matching (int, str, bool, etc.)
        return bool(pat == unwrapped_input)

    def _match_ellipsis(
        self,
        elem_pat: Any,
        rest_pat: Any,
        input_stx: Any,
        bindings: Dict[str, PatternBinding],
    ) -> bool:
        """Match repeating element pattern followed by rest_pat."""
        # Collect all items in input_stx into a python list
        items: List[Any] = []
        curr = input_stx
        while is_pair(curr.datum if isinstance(curr, Syntax) else curr):
            unwrapped = curr.datum if isinstance(curr, Syntax) else curr
            items.append(unwrapped.car)
            curr = unwrapped.cdr

        # Match backwards from rest_pat count if any
        rest_count = 0
        tmp_rest = rest_pat
        while is_pair(tmp_rest):
            rest_count += 1
            tmp_rest = cdr(tmp_rest)

        if len(items) < rest_count:
            return False

        repeat_items = items[: len(items) - rest_count] if rest_count > 0 else items
        rest_items = items[len(items) - rest_count :] if rest_count > 0 else []

        # Find pattern variables inside elem_pat
        pat_vars = self._collect_pattern_vars(elem_pat)
        collected_sub_bindings: Dict[str, List[Any]] = {v: [] for v in pat_vars}

        for item in repeat_items:
            sub_bind: Dict[str, PatternBinding] = {}
            if not self._match_pattern(elem_pat, item, sub_bind):
                return False
            for v in pat_vars:
                if v in sub_bind:
                    collected_sub_bindings[v].append(sub_bind[v].value)

        # Store collected bindings with depth incremented
        for v in pat_vars:
            bindings[v] = PatternBinding(depth=1, value=collected_sub_bindings[v])

        # Match rest_pat
        rest_stx = to_lisp_list(rest_items)
        return self._match_pattern(rest_pat, rest_stx, bindings)

    def _collect_pattern_vars(self, pat: Any) -> List[str]:
        """Collect all pattern variables in a pattern."""
        res: List[str] = []
        if isinstance(pat, Symbol):
            if pat.name not in self.literals and pat.name != "..." and pat.name != "_":
                res.append(pat.name)
        elif is_pair(pat):
            res.extend(self._collect_pattern_vars(car(pat)))
            res.extend(self._collect_pattern_vars(cdr(pat)))
        return res

    def _expand_template(
        self,
        tmpl: Any,
        bindings: Dict[str, PatternBinding],
        use_scope: Scope,
    ) -> Any:
        """Expand a template S-expression substituting bindings with use_scope."""
        if isinstance(tmpl, Symbol):
            if tmpl.name in bindings:
                b = bindings[tmpl.name]
                if b.depth == 0:
                    return b.value
                raise SyntaxError(
                    f"Pattern variable '{tmpl.name}' used outside ellipsis in template"
                )
            # Literal / macro-introduced symbol: attach definition and use scope
            stx = Syntax(tmpl, {self.def_scope, use_scope})
            return stx

        if is_pair(tmpl):
            tmpl_car = car(tmpl)
            tmpl_cdr = cdr(tmpl)

            # Check if followed by ellipsis '...'
            if (
                is_pair(tmpl_cdr)
                and isinstance(car(tmpl_cdr), Symbol)
                and car(tmpl_cdr).name == "..."
            ):
                # Ellipsis expansion!
                expanded_list = self._expand_ellipsis(tmpl_car, bindings, use_scope)
                rest_expanded = self._expand_template(
                    cdr(tmpl_cdr), bindings, use_scope
                )
                return self._splice_into_list(expanded_list, rest_expanded)

            return Syntax(
                Cons(
                    self._expand_template(tmpl_car, bindings, use_scope),
                    self._expand_template(tmpl_cdr, bindings, use_scope),
                ),
                {self.def_scope, use_scope},
            )

        if isinstance(tmpl, Vector):
            new_elems = [
                self._expand_template(e, bindings, use_scope) for e in tmpl.elements
            ]
            return Syntax(Vector(new_elems), {self.def_scope, use_scope})

        # Self-evaluating constant
        return Syntax(tmpl, {self.def_scope, use_scope})

    def _expand_ellipsis(
        self,
        tmpl: Any,
        bindings: Dict[str, PatternBinding],
        use_scope: Scope,
    ) -> List[Any]:
        """Expand a template with ellipsis by iterating over matched lists."""
        vars_in_tmpl = self._collect_pattern_vars(tmpl)
        list_lengths: List[int] = []
        for v in vars_in_tmpl:
            if v in bindings and bindings[v].depth > 0:
                list_lengths.append(len(bindings[v].value))

        if not list_lengths:
            raise SyntaxError(
                "Ellipsis in template does not contain any pattern variables"
            )

        count = list_lengths[0]
        for length_val in list_lengths[1:]:
            if length_val != count:
                raise SyntaxError(
                    "Incompatible ellipsis sub-pattern lengths in template"
                )

        results: List[Any] = []
        for i in range(count):
            # Create iteration slice of bindings
            sub_bindings = dict(bindings)
            for v in vars_in_tmpl:
                if v in bindings and bindings[v].depth > 0:
                    sub_bindings[v] = PatternBinding(
                        depth=bindings[v].depth - 1,
                        value=bindings[v].value[i],
                    )
            results.append(self._expand_template(tmpl, sub_bindings, use_scope))
        return results

    def _splice_into_list(self, head_list: List[Any], tail: Any) -> Any:
        """Construct a Cons list from head_list terminating with tail."""
        res = tail
        for item in reversed(head_list):
            res = Syntax(Cons(item, res), set())
        return res
