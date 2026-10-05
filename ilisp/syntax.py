"""Scope Sets Hygienic Macro System for ILISP (R7RS syntax-rules).

This module implements Matthew Flatt's "Binding as Sets of Scopes" (POPL 2016)
algorithm to provide hygienic macro expansion without variable capture.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Set, Tuple

from ilisp.types import Cons, SourceLocation, Symbol, Vector, car, cdr, is_null, is_pair


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
    node_loc = loc or getattr(datum, "loc", None)
    if isinstance(datum, Symbol):
        return Syntax(datum, sc, node_loc)
    elif isinstance(datum, Cons):
        new_car = datum_to_syntax(datum.car, sc, node_loc)
        new_cdr = datum_to_syntax(datum.cdr, sc, node_loc)
        return Syntax(Cons(new_car, new_cdr, loc=datum.loc), sc, node_loc)
    elif isinstance(datum, Vector):
        new_elems = [datum_to_syntax(e, sc, node_loc) for e in datum.elements]
        return Syntax(Vector(new_elems), sc, node_loc)
    elif isinstance(datum, Syntax):
        return datum
    else:
        # Self-evaluating literals
        return Syntax(datum, sc, node_loc)


def syntax_to_datum(
    stx: Any,
    use_scope: Optional[Scope] = None,
    env: Optional[Any] = None,
    def_env: Optional[Any] = None,
) -> Any:
    """Convert a Syntax object back to a standard Lisp S-expression.

    If use_scope is provided, symbols bearing use_scope that were introduced
    by the macro definition are renamed hygienically to avoid capturing caller variables.
    """
    if isinstance(stx, Syntax):
        d = stx.datum
        if isinstance(d, Symbol):
            # If the symbol has the macro use-scope, rename it hygienically
            if use_scope is not None and use_scope in stx.scopes:
                if d.name in ("...", "_"):
                    return d
                core_forms = {
                    "...",
                    "_",
                    "quote",
                    "lambda",
                    "if",
                    "set!",
                    "begin",
                    "define",
                    "define-values",
                    "define-syntax",
                    "let-syntax",
                    "letrec-syntax",
                    "syntax-rules",
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
                    "syntax-error",
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
                    "caaar",
                    "caadr",
                    "cadar",
                    "caddr",
                    "cdaar",
                    "cdadr",
                    "cddar",
                    "cdddr",
                    "caaaar",
                    "caaadr",
                    "caadar",
                    "caaddr",
                    "cadaar",
                    "cadadr",
                    "caddar",
                    "cadddr",
                    "cdaaar",
                    "cdaadr",
                    "cdadar",
                    "cdaddr",
                    "cddaar",
                    "cddadr",
                    "cdddar",
                    "cddddr",
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
                    "symbol=?",
                    "symbol->string",
                    "string?",
                    "string-append",
                    "string=?",
                    "eq?",
                    "eqv?",
                    "equal?",
                    "boolean?",
                    "boolean=?",
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
                    "write-simple",
                    "write-shared",
                    "write-string",
                    "newline",
                    "read-char",
                    "eof-object?",
                    "load",
                    "current-second",
                    "current-jiffy",
                    "jiffies-per-second",
                    "get-environment-variable",
                    "get-environment-variables",
                    "command-line",
                    "exit",
                    "emergency-exit",
                    "exact-integer-sqrt",
                    "complex?",
                    "make-rectangular",
                    "make-polar",
                    "real-part",
                    "imag-part",
                    "magnitude",
                    "angle",
                    "exp",
                    "log",
                    "sin",
                    "cos",
                    "tan",
                    "asin",
                    "acos",
                    "atan",
                    "char-alphabetic?",
                    "char-numeric?",
                    "char-whitespace?",
                    "char-upper-case?",
                    "char-lower-case?",
                    "digit-value",
                    "char-upcase",
                    "char-downcase",
                    "char-foldcase",
                    "char-ci=?",
                    "char-ci<?",
                    "char-ci>?",
                    "char-ci<=?",
                    "char-ci>=?",
                    "string-upcase",
                    "string-downcase",
                    "string-foldcase",
                    "string-ci=?",
                    "string-ci<?",
                    "string-ci>?",
                    "string-ci<=?",
                    "string-ci>=?",
                    "delay",
                    "delay-force",
                    "force",
                    "make-promise",
                    "promise?",
                    "__make-promise-from-thunk",
                    "case-lambda",
                    "eval",
                    "environment",
                    "interaction-environment",
                }
                if d.name in core_forms:
                    return d
                if env is not None:
                    try:
                        env.root.lookup(d)
                        return d
                    except Exception:
                        pass
                from ilisp.env import get_interaction_environment

                ienv = get_interaction_environment()
                if ienv is not None:
                    try:
                        ienv.root.lookup(d)
                        return d
                    except Exception:
                        pass
                hyg_sym = Symbol.intern(f"{d.name}__hyg_{use_scope.id}")
                if def_env is not None and env is not None:
                    try:
                        val = def_env.lookup(d)
                        env.define(hyg_sym, val)
                    except Exception:
                        pass
                return hyg_sym
            return d
        elif isinstance(d, Cons):
            car_val = syntax_to_datum(d.car, use_scope, env, def_env)
            loc = getattr(d, "loc", None) or getattr(stx, "loc", None)
            if car_val == Symbol.intern("quote"):
                return Cons(car_val, strip_syntax(d.cdr), loc=loc)
            return Cons(
                car_val,
                syntax_to_datum(d.cdr, use_scope, env, def_env),
                loc=loc,
            )
        elif isinstance(d, Vector):
            return Vector([strip_syntax(e) for e in d.elements])
        return d
    elif isinstance(stx, Cons):
        car_val = syntax_to_datum(stx.car, use_scope, env, def_env)
        loc = getattr(stx, "loc", None)
        if car_val == Symbol.intern("quote"):
            return Cons(car_val, strip_syntax(stx.cdr), loc=loc)
        return Cons(
            car_val,
            syntax_to_datum(stx.cdr, use_scope, env, def_env),
            loc=loc,
        )
    elif isinstance(stx, Vector):
        return Vector([strip_syntax(e) for e in stx.elements])
    return stx


def strip_syntax(s: Any) -> Any:
    """Recursively strip all Syntax wrappers without renaming symbols."""
    if isinstance(s, Syntax):
        return strip_syntax(s.datum)
    elif isinstance(s, Cons):
        return Cons(strip_syntax(s.car), strip_syntax(s.cdr))
    elif isinstance(s, Vector):
        return Vector([strip_syntax(e) for e in s.elements])
    return s


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
        ellipsis: str = "...",
        def_env: Optional[Any] = None,
    ) -> None:
        self.name: str = name
        self.literals: Set[str] = set(literals)
        self.rules: List[Tuple[Any, Any]] = rules
        self.ellipsis: str = ellipsis
        if self.ellipsis in self.literals:
            self.ellipsis = "\x00"
        self.def_scope: Scope = Scope(f"def_{name}")
        self.def_env: Optional[Any] = def_env

    def transform(self, input_form: Any, env: Optional[Any] = None) -> Any:
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
                expanded_datum = syntax_to_datum(
                    expanded_stx, use_scope, env=env, def_env=self.def_env
                )
                if (
                    isinstance(expanded_datum, Cons)
                    and expanded_datum.loc is None
                    and hasattr(input_form, "loc")
                ):
                    expanded_datum.loc = getattr(input_form, "loc", None)
                try:
                    from alisp.repair.diagnostic import MacroExpansionRegistry

                    MacroExpansionRegistry.register(
                        input_form,
                        expanded_datum,
                        loc=getattr(input_form, "loc", None),
                    )
                except Exception:
                    pass
                return expanded_datum

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

            # Check if followed by ellipsis
            if (
                is_pair(pat_cdr)
                and isinstance(car(pat_cdr), Symbol)
                and car(pat_cdr).name == self.ellipsis
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

        # Match rest_pat preserving improper list tail
        tail = curr
        rest_stx = tail
        for item in reversed(rest_items):
            rest_stx = Cons(item, rest_stx)
        return self._match_pattern(rest_pat, rest_stx, bindings)

    def _collect_pattern_vars(self, pat: Any) -> List[str]:
        """Collect all pattern variables in a pattern."""
        res: List[str] = []
        if isinstance(pat, Symbol):
            if (
                pat.name not in self.literals
                and pat.name != self.ellipsis
                and pat.name != "_"
            ):
                res.append(pat.name)
        elif is_pair(pat):
            res.extend(self._collect_pattern_vars(car(pat)))
            res.extend(self._collect_pattern_vars(cdr(pat)))
        return res

    def _expand_escaped_template(
        self,
        tmpl: Any,
        bindings: Dict[str, PatternBinding],
        use_scope: Scope,
    ) -> Any:
        """Expand a template where ellipsis is escaped (treated as literal)."""
        if isinstance(tmpl, Symbol):
            if tmpl.name in bindings:
                b = bindings[tmpl.name]
                if b.depth == 0:
                    return b.value
            return Syntax(tmpl, {self.def_scope, use_scope})
        if is_pair(tmpl):
            return Syntax(
                Cons(
                    self._expand_escaped_template(car(tmpl), bindings, use_scope),
                    self._expand_escaped_template(cdr(tmpl), bindings, use_scope),
                ),
                {self.def_scope, use_scope},
            )
        if isinstance(tmpl, Vector):
            new_elems = [
                self._expand_escaped_template(e, bindings, use_scope)
                for e in tmpl.elements
            ]
            return Syntax(Vector(new_elems), {self.def_scope, use_scope})
        return Syntax(tmpl, {self.def_scope, use_scope})

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

            # R7RS 4.3.2: (... <template>) escapes ellipsis in <template>
            if (
                isinstance(tmpl_car, Symbol)
                and tmpl_car.name == self.ellipsis
                and is_pair(tmpl_cdr)
                and is_null(cdr(tmpl_cdr))
            ):
                return self._expand_escaped_template(car(tmpl_cdr), bindings, use_scope)

            # Check if followed by ellipsis
            if (
                is_pair(tmpl_cdr)
                and isinstance(car(tmpl_cdr), Symbol)
                and car(tmpl_cdr).name == self.ellipsis
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
            return [self._expand_template(tmpl, bindings, use_scope)]

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
