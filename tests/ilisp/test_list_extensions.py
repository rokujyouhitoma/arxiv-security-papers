"""Unit and integration tests for R7RS 6.4 List Extensions in ILISP.

Covers:
- list? (with Floyd's cycle detection)
- make-list
- list-tail, list-ref, list-set!
- list-copy
- set-car!, set-cdr!
- multi-argument map and for-each (with shortest-length sync)
- Backend A transpilation interoperability
"""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import NilType, Symbol, to_py_list


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestListPredicateAndCycles:
    """Tests for list? predicate and cycle resilience (R7RS 6.4)."""

    def test_list_predicate_basic(self) -> None:
        assert run_code("(list? '())") is True
        assert run_code("(list? '(1 2 3))") is True
        assert run_code("(list? (list 1 2 3))") is True
        assert run_code("(list? '(1 2 . 3))") is False
        assert run_code("(list? 42)") is False
        assert run_code("(list? #(1 2 3))") is False
        assert run_code('(list? "hello")') is False

    def test_list_predicate_cyclic_list(self) -> None:
        # Create a cyclic list: (define x (list 1 2 3)) (set-cdr! (cddr x) x)
        code = """
        (define x (list 1 2 3))
        (set-cdr! (cdr (cdr x)) x)
        (list? x)
        """
        assert run_code(code) is False

    def test_list_predicate_inner_cycle(self) -> None:
        # Tail has a cycle: (define head (cons 0 (list 1 2))) (set-cdr! (cddr head) (cdr head))
        code = """
        (define sub (list 1 2))
        (define head (cons 0 sub))
        (set-cdr! (cdr sub) sub)
        (list? head)
        """
        assert run_code(code) is False


class TestMakeList:
    """Tests for make-list primitive (R7RS 6.4)."""

    def test_make_list_zero(self) -> None:
        res = run_code("(make-list 0)")
        assert isinstance(res, NilType)

    def test_make_list_with_fill(self) -> None:
        res = run_code("(make-list 4 'val)")
        assert to_py_list(res) == [Symbol.intern("val")] * 4

    def test_make_list_negative_error(self) -> None:
        with pytest.raises(ValueError):
            run_code("(make-list -1)")


class TestListTailAndRef:
    """Tests for list-tail and list-ref primitives (R7RS 6.4)."""

    def test_list_tail_basic(self) -> None:
        assert to_py_list(run_code("(list-tail '(a b c d) 0)")) == [
            Symbol.intern("a"),
            Symbol.intern("b"),
            Symbol.intern("c"),
            Symbol.intern("d"),
        ]
        assert to_py_list(run_code("(list-tail '(a b c d) 2)")) == [
            Symbol.intern("c"),
            Symbol.intern("d"),
        ]
        assert isinstance(run_code("(list-tail '(a b c d) 4)"), NilType)

    def test_list_tail_improper(self) -> None:
        assert run_code("(list-tail '(a b . c) 2)") == Symbol.intern("c")

    def test_list_tail_bounds_error(self) -> None:
        with pytest.raises(IndexError):
            run_code("(list-tail '(a b) 3)")

    def test_list_ref_basic(self) -> None:
        assert run_code("(list-ref '(10 20 30 40) 0)") == 10
        assert run_code("(list-ref '(10 20 30 40) 2)") == 30
        assert run_code("(list-ref '(10 20 30 40) 3)") == 40

    def test_list_ref_bounds_error(self) -> None:
        with pytest.raises(IndexError):
            run_code("(list-ref '(10 20) 2)")


class TestListSetAndMutation:
    """Tests for list-set!, set-car!, and set-cdr! (R7RS 6.4)."""

    def test_set_car_and_set_cdr(self) -> None:
        code = """
        (define p (cons 1 2))
        (set-car! p 10)
        (set-cdr! p 20)
        (list (car p) (cdr p))
        """
        assert to_py_list(run_code(code)) == [10, 20]

    def test_list_set_bang(self) -> None:
        code = """
        (define l (list 10 20 30 40))
        (list-set! l 1 999)
        l
        """
        assert to_py_list(run_code(code)) == [10, 999, 30, 40]

    def test_list_set_bang_bounds_error(self) -> None:
        with pytest.raises(IndexError):
            run_code("(list-set! (list 1 2) 5 999)")


class TestListCopy:
    """Tests for list-copy primitive (R7RS 6.4)."""

    def test_list_copy_spine_isolation(self) -> None:
        code = """
        (define orig (list 1 2 3))
        (define copy (list-copy orig))
        (set-car! orig 100)
        (set-car! (cdr orig) 200)
        (list orig copy)
        """
        res = run_code(code)
        py_res = to_py_list(res)
        assert to_py_list(py_res[0]) == [100, 200, 3]
        assert to_py_list(py_res[1]) == [1, 2, 3]

    def test_list_copy_improper(self) -> None:
        code = """
        (define dotted (cons 1 (cons 2 'end)))
        (define copy (list-copy dotted))
        (list (car copy) (car (cdr copy)) (cdr (cdr copy)))
        """
        res = run_code(code)
        assert to_py_list(res) == [1, 2, Symbol.intern("end")]

    def test_list_copy_non_list(self) -> None:
        assert run_code("(list-copy 42)") == 42
        assert run_code("(list-copy 'sym)") == Symbol.intern("sym")


class TestMultiArgMapAndForEach:
    """Tests for multi-argument map and for-each (R7RS 6.4)."""

    def test_map_single_list(self) -> None:
        res = run_code("(map (lambda (x) (* x 2)) '(1 2 3 4))")
        assert to_py_list(res) == [2, 4, 6, 8]

    def test_map_multiple_same_length(self) -> None:
        code = """
        (map + '(1 2 3) '(10 20 30) '(100 200 300))
        """
        assert to_py_list(run_code(code)) == [111, 222, 333]

    def test_map_multiple_different_lengths_sync(self) -> None:
        # Terminates at shortest length (length 2)
        code = """
        (map list '(a b) '(1 2 3 4 5) '(#t #f #t))
        """
        res = run_code(code)
        py_res = to_py_list(res)
        assert len(py_res) == 2
        assert to_py_list(py_res[0]) == [Symbol.intern("a"), 1, True]
        assert to_py_list(py_res[1]) == [Symbol.intern("b"), 2, False]

    def test_for_each_multi_list(self) -> None:
        code = """
        (define acc 0)
        (for-each (lambda (a b) (set! acc (+ acc (* a b))))
                  '(1 2 3 4)
                  '(10 20 30))
        acc
        """
        # 1*10 + 2*20 + 3*30 = 10 + 40 + 90 = 140 (stops after 3rd item)
        assert run_code(code) == 140


class TestBackendAListIntegration:
    """Tests compiling list operations through py_codegen."""

    def test_compile_make_list_and_ref(self) -> None:
        code = """
        (define (make-and-query n val)
          (let ((lst (make-list n val)))
            (list-set! lst 1 777)
            (list (list-ref lst 0) (list-ref lst 1) (length lst))))
        (make-and-query 3 100)
        """
        res = compile_ilisp(code)
        assert to_py_list(res) == [100, 777, 3]

    def test_compile_multi_map(self) -> None:
        code = """
        (define (zip-sum l1 l2)
          (map + l1 l2))
        (zip-sum '(1 2 3) '(10 20 30))
        """
        res = compile_ilisp(code)
        assert to_py_list(res) == [11, 22, 33]
