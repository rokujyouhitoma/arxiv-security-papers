"""Unit and integration tests for R7RS 4.2 Derived Expressions in ILISP.

Covers:
- case-lambda (R7RS 4.2.9)
- cond => and (test) syntax (R7RS 4.2.1)
- case => syntax (R7RS 4.2.1)
- delay, delay-force, force, promise?, make-promise (R7RS 4.2.5)
- apply (R7RS 6.4)
- Backend A transpilation interoperability
"""

from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import NilType, to_py_list


def run_code(code: str) -> Any:
    """Helper to evaluate ILISP code with standard environment."""
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    res = None
    for e in exprs:
        res = eval_expr(e, env)
    return res


class TestApplyPrimitive:
    """Tests for apply primitive (R7RS 6.4)."""

    def test_apply_simple(self) -> None:
        res = run_code("(apply + '(1 2 3 4))")
        assert res == 10

    def test_apply_with_leading_args(self) -> None:
        res = run_code("(apply + 10 20 '(1 2 3))")
        assert res == 36

    def test_apply_empty_list(self) -> None:
        res = run_code("(apply list '())")
        assert isinstance(res, NilType)

    def test_apply_type_error(self) -> None:
        with pytest.raises(TypeError):
            run_code("(apply 123 '(1 2))")


class TestCondArrowSyntax:
    """Tests for cond => recipient and single-value test syntax (R7RS 4.2.1)."""

    def test_cond_arrow_match(self) -> None:
        code = """
        (define alist '((a . 1) (b . 2) (c . 3)))
        (cond ((assoc 'b alist) => cdr)
              (else #f))
        """
        assert run_code(code) == 2

    def test_cond_arrow_fallthrough(self) -> None:
        code = """
        (define alist '((a . 1) (b . 2)))
        (cond ((assoc 'z alist) => cdr)
              (else 'fallback))
        """
        from ilisp.types import Symbol

        assert run_code(code) == Symbol.intern("fallback")

    def test_cond_single_test_expression(self) -> None:
        code = """
        (cond (#f)
              (3)
              (else 99))
        """
        assert run_code(code) == 3


class TestCaseArrowSyntax:
    """Tests for case => recipient syntax (R7RS 4.2.1)."""

    def test_case_arrow_match(self) -> None:
        code = """
        (case (* 2 3)
          ((2 3 5 7) 'prime)
          ((1 4 6 8 9) => (lambda (x) (* x 10)))
          (else 'other))
        """
        assert run_code(code) == 60

    def test_case_arrow_else(self) -> None:
        code = """
        (case 99
          ((1 2 3) 'small)
          (else => (lambda (x) (+ x 1))))
        """
        assert run_code(code) == 100


class TestLazyEvaluation:
    """Tests for delay, delay-force, force, promise?, make-promise (R7RS 4.2.5)."""

    def test_promise_predicate(self) -> None:
        res = run_code("(promise? (delay (+ 1 2)))")
        assert res is True
        assert run_code("(promise? 42)") is False
        assert run_code("(promise? '())") is False

    def test_force_simple(self) -> None:
        assert run_code("(force (delay (+ 10 20)))") == 30

    def test_force_memoization(self) -> None:
        code = """
        (define counter 0)
        (define p (delay (begin (set! counter (+ counter 1)) counter)))
        (define r1 (force p))
        (define r2 (force p))
        (list r1 r2 counter)
        """
        res = run_code(code)
        assert to_py_list(res) == [1, 1, 1]

    def test_make_promise_and_force_non_promise(self) -> None:
        code = """
        (define p (make-promise 42))
        (list (promise? p) (force p) (force 100))
        """
        res = run_code(code)
        assert to_py_list(res) == [True, 42, 100]

    def test_delay_force_stream(self) -> None:
        # Lazy stream with delay-force
        code = """
        (define (stream-filter pred stream)
          (delay-force
            (if (null? (force stream))
                (make-promise '())
                (let ((head (car (force stream)))
                      (tail (cdr (force stream))))
                  (if (pred head)
                      (make-promise (cons head (stream-filter pred tail)))
                      (stream-filter pred tail))))))

        (define (stream-range a b)
          (delay
            (if (> a b)
                '()
                (cons a (stream-range (+ a 1) b)))))

        (define s (stream-range 1 10))
        (define evens (stream-filter even? s))
        (car (force evens))
        """
        assert run_code(code) == 2


class TestCaseLambda:
    """Tests for case-lambda (R7RS 4.2.9)."""

    def test_case_lambda_fixed_arities(self) -> None:
        code = """
        (define f
          (case-lambda
            (() 0)
            ((x) (* x 2))
            ((x y) (+ x y))))
        (list (f) (f 10) (f 3 4))
        """
        assert to_py_list(run_code(code)) == [0, 20, 7]

    def test_case_lambda_varargs_rest(self) -> None:
        code = """
        (define var-f
          (case-lambda
            ((x) x)
            ((x y) (+ x y))
            ((x y . rest) (cons (+ x y) rest))))
        (list (var-f 5)
              (var-f 3 4)
              (var-f 1 2 3 4 5))
        """
        res = run_code(code)
        py_res = to_py_list(res)
        assert py_res[0] == 5
        assert py_res[1] == 7
        assert to_py_list(py_res[2]) == [3, 3, 4, 5]

    def test_case_lambda_catchall_symbol(self) -> None:
        code = """
        (define cl
          (case-lambda
            (() 'none)
            (args (cons 'got args))))
        (list (cl) (cl 1 2 3))
        """
        from ilisp.types import Symbol

        res = to_py_list(run_code(code))
        assert res[0] == Symbol.intern("none")
        assert to_py_list(res[1]) == [Symbol.intern("got"), 1, 2, 3]

    def test_case_lambda_no_match_raises(self) -> None:
        code = """
        (define f
          (case-lambda
            ((x y) (+ x y))))
        (f 1)
        """
        with pytest.raises(Exception):
            run_code(code)


class TestBackendAIntegration:
    """Tests compiling derived control constructs through py_codegen."""

    def test_compile_apply(self) -> None:
        code = """
        (define (sum-all lst)
          (apply + lst))
        (sum-all '(10 20 30 40))
        """
        assert compile_ilisp(code) == 100

    def test_compile_cond_arrow(self) -> None:
        code = """
        (define (find-val k alist)
          (cond ((assoc k alist) => cdr)
                (else 0)))
        (find-val 'target '((a . 10) (target . 99)))
        """
        assert compile_ilisp(code) == 99

    def test_compile_case_lambda(self) -> None:
        code = """
        (define multi
          (case-lambda
            (() 42)
            ((a) (* a 2))
            ((a b) (+ a b))))
        (list (multi) (multi 5) (multi 10 20))
        """
        res = compile_ilisp(code)
        assert to_py_list(res) == [42, 10, 30]

    def test_compile_lazy_promise(self) -> None:
        code = """
        (define p (delay (* 6 7)))
        (force p)
        """
        assert compile_ilisp(code) == 42
