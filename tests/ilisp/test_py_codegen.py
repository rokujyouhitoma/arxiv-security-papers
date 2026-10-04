"""Unit tests for ILISP Python AST Code Generation Backend (Backend A).

Tests cover:
- Basic literals, variables, and primitive calls
- Definition and lambda expressions
- Self Tail-Call Optimization (Self-TCO) with deep recursion
- Cell boxing and mutable state in closures (set!)
- Standard library higher-order procedures and macro integration
"""

import time

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.types import NIL, Cons, to_py_list


class TestASTCompilerBasics:
    """Basic literals, arithmetic, and conditional expressions."""

    def test_literals(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        assert compile_ilisp("42", env=env) == 42
        assert compile_ilisp("3.14", env=env) == 3.14
        assert compile_ilisp('"hello world"', env=env) == "hello world"
        assert compile_ilisp("#t", env=env) is True
        assert compile_ilisp("#f", env=env) is False
        assert compile_ilisp("'()", env=env) is NIL

    def test_basic_arithmetic(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        assert compile_ilisp("(+ 1 2 3 4)", env=env) == 10
        assert compile_ilisp("(- 20 5 3)", env=env) == 12
        assert compile_ilisp("(* 2 3 4)", env=env) == 24
        assert compile_ilisp("(quotient 10 3)", env=env) == 3
        assert compile_ilisp("(remainder 10 3)", env=env) == 1

    def test_conditionals_and_truthiness(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        assert compile_ilisp("(if #t 1 2)", env=env) == 1
        assert compile_ilisp("(if #f 1 2)", env=env) == 2
        # In Scheme, 0 and empty list are truthy
        assert compile_ilisp("(if 0 100 200)", env=env) == 100
        assert compile_ilisp("(if '() 100 200)", env=env) == 100

    def test_quote(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        res = compile_ilisp("'(a b c)", env=env)
        assert isinstance(res, Cons)
        elements = to_py_list(res)
        assert [e.name for e in elements] == ["a", "b", "c"]

    def test_begin_and_define(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        code = """
        (define x 10)
        (define y 20)
        (+ x y)
        """
        assert compile_ilisp(code, env=env) == 30


class TestSelfTailCallOptimization:
    """Validation of Self-TCO compilation to while True loops."""

    def test_deep_self_tail_recursion(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        code = """
        (define (countdown n)
          (if (= n 0)
              "done"
              (countdown (- n 1))))
        (countdown 100000)
        """
        t0 = time.time()
        res = compile_ilisp(code, env=env)
        elapsed = time.time() - t0
        assert res == "done"
        assert elapsed < 1.0, f"Self-TCO execution too slow: {elapsed}s"

    def test_tail_recursive_accumulator(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        code = """
        (define (sum-acc n acc)
          (if (= n 0)
              acc
              (sum-acc (- n 1) (+ acc n))))
        (sum-acc 1000 0)
        """
        assert compile_ilisp(code, env=env) == 500500


class TestCellMutationAndClosures:
    """Cell boxing and mutable closures."""

    def test_set_bang_local(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        code = """
        (define x 10)
        (set! x 42)
        x
        """
        assert compile_ilisp(code, env=env) == 42

    def test_counter_closure(self) -> None:
        env = make_initial_env(preload_stdlib=False)
        code = """
        (define (make-counter init)
          (lambda ()
            (begin
              (set! init (+ init 1))
              init)))
        (define c1 (make-counter 0))
        (define c2 (make-counter 100))
        (c1)
        (c1)
        (c2)
        (c1)
        """
        assert compile_ilisp(code, env=env) == 3


class TestStandardLibraryAndInterop:
    """Integration with stdlib macros and higher order functions."""

    def test_stdlib_macros(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = """
        (let ((a 10) (b 20))
          (when (< a b)
            (+ a b)))
        """
        assert compile_ilisp(code, env=env) == 30

        cond_code = """
        (define (grade score)
          (cond
            ((= score 100) 'perfect)
            ((< score 60) 'fail)
            (else 'pass)))
        (list (grade 100) (grade 80) (grade 50))
        """
        res = compile_ilisp(cond_code, env=env)
        items = [x.name for x in to_py_list(res)]
        assert items == ["perfect", "pass", "fail"]

    def test_higher_order_map_filter_fold(self) -> None:
        env = make_initial_env(preload_stdlib=True)
        code = """
        (fold-left + 0
          (map (lambda (x) (* x x))
            (filter (lambda (x) (= (remainder x 2) 0))
              '(1 2 3 4 5 6 7 8 9 10))))
        """
        assert compile_ilisp(code, env=env) == 220

    def test_run_string_backend_integration(self) -> None:
        from ilisp.repl import run_string

        code = "(let ((x 10) (y 20)) (* x y))"
        interp_res = run_string(code, backend="interp")
        ast_res = run_string(code, backend="py_ast")
        assert interp_res == 200
        assert ast_res == 200
