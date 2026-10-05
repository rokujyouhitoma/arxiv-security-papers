"""ALisp Contract Predicate Combinators.

Provides and/c, or/c, not/c, any/c, none/c, and equal/c predicate combinators
usable in both Python and Scheme ALisp contract declarations.
"""

from __future__ import annotations

from typing import Any, Callable

from ilisp.evaluator import _apply_procedure
from ilisp.types import Primitive, Procedure


def _call_predicate(pred: Any, val: Any) -> bool:
    """Evaluate a predicate on a value adhering to Scheme truthiness rules.

    In Scheme, only #f (Python False) is falsy. All other values (including 0,
    empty lists, and empty strings) are truthy.
    """
    if isinstance(pred, Procedure):
        res = _apply_procedure(pred, [val])
    elif callable(pred):
        res = pred(val)
    else:
        raise TypeError(f"Contract predicate must be callable, got {pred!r}")
    return res is not False


def any_c(*args: Any) -> Any:
    """Contract predicate that always succeeds, or returns predicate if called with 0 arguments."""
    if not args:
        return any_c
    return True


def none_c(*args: Any) -> Any:
    """Contract predicate that always fails, or returns predicate if called with 0 arguments."""
    if not args:
        return none_c
    return False


def and_c(*preds: Any) -> Callable[[Any], bool]:
    """Return a compound predicate that succeeds only if all predicates succeed."""

    def _combined_and(val: Any) -> bool:
        for p in preds:
            if not _call_predicate(p, val):
                return False
        return True

    return _combined_and


def or_c(*preds: Any) -> Callable[[Any], bool]:
    """Return a compound predicate that succeeds if any predicate succeeds."""

    def _combined_or(val: Any) -> bool:
        if not preds:
            return False
        for p in preds:
            if _call_predicate(p, val):
                return True
        return False

    return _combined_or


def not_c(pred: Any) -> Callable[[Any], bool]:
    """Return a compound predicate that negates the given predicate."""

    def _negated(val: Any) -> bool:
        return not _call_predicate(pred, val)

    return _negated


def equal_c(expected: Any) -> Callable[[Any], bool]:
    """Return a predicate checking structural equality with the expected value."""

    def _eq(val: Any) -> bool:
        return bool(val == expected)

    return _eq


def make_and_c_primitive() -> Primitive:
    """Scheme primitive (and/c pred ...) returning a compound predicate procedure."""

    def _prim_and_c(*preds: Any) -> Primitive:
        fn = and_c(*preds)
        name = f"(and/c {' '.join(getattr(p, 'name', repr(p)) for p in preds)})"
        return Primitive(name, fn)

    return Primitive("and/c", _prim_and_c)


def make_or_c_primitive() -> Primitive:
    """Scheme primitive (or/c pred ...) returning a compound predicate procedure."""

    def _prim_or_c(*preds: Any) -> Primitive:
        fn = or_c(*preds)
        name = f"(or/c {' '.join(getattr(p, 'name', repr(p)) for p in preds)})"
        return Primitive(name, fn)

    return Primitive("or/c", _prim_or_c)


def make_not_c_primitive() -> Primitive:
    """Scheme primitive (not/c pred) returning a negated predicate procedure."""

    def _prim_not_c(pred: Any) -> Primitive:
        fn = not_c(pred)
        name = f"(not/c {getattr(pred, 'name', repr(pred))})"
        return Primitive(name, fn)

    return Primitive("not/c", _prim_not_c)


def make_equal_c_primitive() -> Primitive:
    """Scheme primitive (equal/c expected) returning an equality check predicate."""

    def _prim_equal_c(expected: Any) -> Primitive:
        fn = equal_c(expected)
        name = f"(equal/c {expected!r})"
        return Primitive(name, fn)

    return Primitive("equal/c", _prim_equal_c)
