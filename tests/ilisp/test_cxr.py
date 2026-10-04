"""Tests for R7RS 7.1.1 (scheme cxr) list accessors in ILISP."""

from typing import Any

import pytest

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import NIL, Cons, Symbol


def eval_code(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


def test_3_step_accessors_nested_tree() -> None:
    """Test all 8 3-step accessors (caaar to cdddr) on a complete binary tree of depth 3."""
    code = """
    (define tree '(((1 . 2) . (3 . 4)) . ((5 . 6) . (7 . 8))))
    (list (caaar tree) (cdaar tree)
          (cadar tree) (cddar tree)
          (caadr tree) (cdadr tree)
          (caddr tree) (cdddr tree))
    """
    res = eval_code(code)
    # Convert Cons list to Python list
    from ilisp.types import to_py_list

    assert to_py_list(res) == [1, 2, 3, 4, 5, 6, 7, 8]


def test_4_step_accessors_nested_tree() -> None:
    """Test all 16 4-step accessors (caaaar to cddddr) on a complete binary tree of depth 4."""
    code = """
    (define tree4
      '((((1 . 2) . (3 . 4)) . ((5 . 6) . (7 . 8))) .
        (((9 . 10) . (11 . 12)) . ((13 . 14) . (15 . 16)))))
    (list (caaaar tree4) (cdaaar tree4)
          (cadaar tree4) (cddaar tree4)
          (caadar tree4) (cdadar tree4)
          (caddar tree4) (cdddar tree4)
          (caaadr tree4) (cdaadr tree4)
          (cadadr tree4) (cddadr tree4)
          (caaddr tree4) (cdaddr tree4)
          (cadddr tree4) (cddddr tree4))
    """
    res = eval_code(code)
    from ilisp.types import to_py_list

    assert to_py_list(res) == list(range(1, 17))


def test_cxr_on_standard_proper_lists() -> None:
    """Test common cxr idioms on standard proper lists."""
    assert eval_code("(caddr '(10 20 30 40 50 60))") == 30
    assert eval_code("(cadddr '(10 20 30 40 50 60))") == 40
    assert eval_code("(car (cddddr '(10 20 30 40 50 60)))") == 50
    assert eval_code("(cadr (cddddr '(10 20 30 40 50 60)))") == 60


def test_cxr_on_nested_sublists() -> None:
    """Test cxr extraction on nested list expressions."""
    code = "(define l '((a (b c) d) (e f)))"
    assert eval_code(f"{code} (cadar l)") == Cons(
        Symbol.intern("b"), Cons(Symbol.intern("c"), NIL)
    )
    assert eval_code(f"{code} (car (cadar l))") == Symbol.intern("b")
    assert eval_code(f"{code} (cadr (cadar l))") == Symbol.intern("c")


def test_cxr_type_errors() -> None:
    """Test that cxr accessors raise TypeError when traversing non-pair structures."""
    with pytest.raises(TypeError):
        eval_code("(caaar 100)")

    with pytest.raises(TypeError):
        eval_code("(caddr '(1 2))")

    with pytest.raises(TypeError):
        eval_code("(cadddr '(1 2 3))")


def test_scheme_cxr_library_import() -> None:
    """Test importing (scheme cxr) library via R7RS import-set."""
    res = eval_code("""
        (import (scheme cxr))
        (caddr '(a b c d))
        """)
    assert res == Symbol.intern("c")

    res4 = eval_code("""
        (import (scheme cxr))
        (cadddr '(a b c d e))
        """)
    assert res4 == Symbol.intern("d")


def test_scheme_cxr_import_modifiers() -> None:
    """Test importing with 'only' and 'prefix' modifiers."""
    res = eval_code("""
        (import (prefix (scheme cxr) cxr:))
        (cxr:caddr '(1 2 3 4))
        """)
    assert res == 3

    res_only = eval_code("""
        (import (only (scheme cxr) caaar cdddr))
        (cdddr '((1 . 2) . (3 . (4 . 5))))
        """)
    assert res_only == 5
