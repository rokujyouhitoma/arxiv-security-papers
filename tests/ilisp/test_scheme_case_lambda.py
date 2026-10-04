"""Unit tests for R7RS (scheme case-lambda) library."""

import pytest

from ilisp.env import Environment
from ilisp.evaluator import eval_expr
from ilisp.module import GLOBAL_LIBRARY_REGISTRY
from ilisp.reader import read_all
from ilisp.types import SchemeException, Symbol, to_py_list


class TestSchemeCaseLambdaModule:
    """Test (scheme case-lambda) library registration and dispatch semantics."""

    def test_library_registered(self) -> None:
        assert GLOBAL_LIBRARY_REGISTRY.has(("scheme", "case-lambda"))
        lib = GLOBAL_LIBRARY_REGISTRY.get(("scheme", "case-lambda"))
        assert lib is not None
        assert Symbol.intern("case-lambda") in lib.exports

    def test_basic_arity_dispatch(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme case-lambda))
        (define f
          (case-lambda
            (() "zero")
            ((x) (list "one" x))
            ((x y) (list "two" x y))))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(f)")[0], env) == "zero"
        assert to_py_list(eval_expr(read_all("(f 10)")[0], env)) == ["one", 10]
        assert to_py_list(eval_expr(read_all("(f 10 20)")[0], env)) == [
            "two",
            10,
            20,
        ]

    def test_rest_argument_dispatch(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme case-lambda))
        (define sum-or-product
          (case-lambda
            ((a) (+ a 100))
            ((a b) (* a b))
            ((a b c . rest) (+ a b c (length rest)))))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(sum-or-product 5)")[0], env) == 105
        assert eval_expr(read_all("(sum-or-product 3 4)")[0], env) == 12
        assert eval_expr(read_all("(sum-or-product 1 2 3)")[0], env) == 6
        assert eval_expr(read_all("(sum-or-product 1 2 3 4 5)")[0], env) == 8

    def test_single_symbol_formals(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme case-lambda))
        (define collect
          (case-lambda
            (() 'empty)
            (args args)))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(collect)")[0], env) == Symbol.intern("empty")
        assert to_py_list(eval_expr(read_all("(collect 1 2 3)")[0], env)) == [
            1,
            2,
            3,
        ]

    def test_no_matching_clause_error(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (scheme case-lambda))
        (define strict-fn
          (case-lambda
            ((x) x)))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        with pytest.raises((SchemeException, Exception)):
            eval_expr(read_all("(strict-fn 1 2 3)")[0], env)

    def test_rename_import(self) -> None:
        env = Environment()
        code = """
        (import (scheme base) (rename (scheme case-lambda) (case-lambda my-case-fn)))
        (define g
          (my-case-fn
            (() 0)
            ((x) 1)))
        """
        for expr in read_all(code):
            eval_expr(expr, env)

        assert eval_expr(read_all("(g)")[0], env) == 0
        assert eval_expr(read_all("(g 42)")[0], env) == 1
