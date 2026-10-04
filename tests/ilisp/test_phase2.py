"""Unit tests for ILISP Phase 2 R7RS Core Features.

Tests cover:
- Quasiquote desugaring, unquote, and unquote-splicing (`, ,, ,@)
- Vectors (#(...) literals, vector?, make-vector, vector-ref, vector-set!, length, conversions)
- Multiple return values (values, call-with-values, let-values, let*-values)
- Continuations (call/cc one-shot escape)
- Exceptions (raise, with-exception-handler, guard)
- Case macro
- Equivalence between Tree-walk evaluator (interp) and Python AST transpiler (py_ast)
"""

import pytest

from ilisp.env import make_initial_env
from ilisp.repl import run_string
from ilisp.types import Cons, Vector, to_py_list


class TestQuasiquote:
    """Validation of quasiquote, unquote, and unquote-splicing."""

    def test_basic_quasiquote(self) -> None:
        env = make_initial_env()
        res = run_string("`(1 2 3)", env=env)
        assert isinstance(res, Cons)
        assert to_py_list(res) == [1, 2, 3]

    def test_unquote_evaluation(self) -> None:
        env = make_initial_env()
        res = run_string("`(1 ,(+ 2 3) 6)", env=env)
        assert to_py_list(res) == [1, 5, 6]

    def test_unquote_splicing(self) -> None:
        env = make_initial_env()
        res = run_string("`(1 ,@'(2 3 4) 5)", env=env)
        assert to_py_list(res) == [1, 2, 3, 4, 5]

        res_head = run_string("`(,@'(a b) c)", env=env)
        items = [x.name for x in to_py_list(res_head)]
        assert items == ["a", "b", "c"]

    def test_vector_quasiquote(self) -> None:
        env = make_initial_env()
        res = run_string("`#(1 ,(+ 2 2) 5)", env=env)
        assert isinstance(res, Vector)
        assert res.elements == [1, 4, 5]

        res_spliced = run_string("`#(0 ,@'(1 2) 3)", env=env)
        assert isinstance(res_spliced, Vector)
        assert res_spliced.elements == [0, 1, 2, 3]


class TestVectors:
    """Validation of Vector data type and R7RS primitives."""

    def test_vector_literals_and_predicates(self) -> None:
        env = make_initial_env()
        res = run_string("#(1 2 3 4)", env=env)
        assert isinstance(res, Vector)
        assert len(res) == 4
        assert res[0] == 1
        assert res[3] == 4

        assert run_string("(vector? #(1 2))", env=env) is True
        assert run_string("(vector? '(1 2))", env=env) is False

    def test_vector_primitives(self) -> None:
        env = make_initial_env()
        assert run_string("(vector-length #(10 20 30))", env=env) == 3
        assert run_string("(vector-ref #(10 20 30) 1)", env=env) == 20

        code_set = """
        (define v (vector 1 2 3))
        (vector-set! v 1 99)
        (vector-ref v 1)
        """
        assert run_string(code_set, env=env) == 99

    def test_vector_conversions(self) -> None:
        env = make_initial_env()
        v_to_l = run_string("(vector->list #(10 20 30))", env=env)
        assert to_py_list(v_to_l) == [10, 20, 30]

        l_to_v = run_string("(list->vector '(100 200))", env=env)
        assert isinstance(l_to_v, Vector)
        assert l_to_v.elements == [100, 200]


class TestMultipleValues:
    """Validation of R7RS values and call-with-values."""

    def test_call_with_values(self) -> None:
        env = make_initial_env()
        code = "(call-with-values (lambda () (values 10 20)) +)"
        assert run_string(code, env=env) == 30

    def test_let_values(self) -> None:
        env = make_initial_env()
        code = """
        (let-values (((a b) (values 10 20))
                     ((c) 30))
          (+ a b c))
        """
        assert run_string(code, env=env) == 60

    def test_let_star_values(self) -> None:
        env = make_initial_env()
        code = """
        (let*-values (((a b) (values 2 3))
                      ((c) (* a b)))
          (+ a b c))
        """
        assert run_string(code, env=env) == 11


class TestContinuations:
    """Validation of call/cc one-shot escape continuations."""

    def test_call_cc_normal_return(self) -> None:
        env = make_initial_env()
        assert run_string("(call/cc (lambda (k) 42))", env=env) == 42

    def test_call_cc_escape(self) -> None:
        env = make_initial_env()
        code = "(+ 1 (call/cc (lambda (k) (+ 2 (k 10) 3))))"
        assert run_string(code, env=env) == 11

    def test_call_cc_oneshot_guard(self) -> None:
        env = make_initial_env()
        code = """
        (define saved-k #f)
        (call/cc (lambda (k) (set! saved-k k) 1))
        (saved-k 2)
        """
        with pytest.raises(RuntimeError, match="cannot be invoked multiple times"):
            run_string(code, env=env)


class TestExceptionsAndGuard:
    """Validation of raise, with-exception-handler, and guard."""

    def test_with_exception_handler(self) -> None:
        env = make_initial_env()
        code = """
        (with-exception-handler
          (lambda (err) (+ err 100))
          (lambda () (raise 42)))
        """
        assert run_string(code, env=env) == 142

    def test_guard_macro(self) -> None:
        env = make_initial_env()
        code = """
        (define (test-guard val)
          (guard (e ((= e 1) "one")
                    ((= e 2) "two")
                    (else "other"))
            (raise val)))
        (list (test-guard 1) (test-guard 2) (test-guard 99))
        """
        res = run_string(code, env=env)
        assert to_py_list(res) == ["one", "two", "other"]

    def test_guard_without_exception(self) -> None:
        env = make_initial_env()
        code = "(guard (e (else 'error)) (+ 10 20))"
        assert run_string(code, env=env) == 30


class TestCaseMacro:
    """Validation of case macro."""

    def test_case_macro(self) -> None:
        env = make_initial_env()
        code = """
        (define (classify x)
          (case x
            ((1 3 5 7 9) 'odd)
            ((0 2 4 6 8) 'even)
            (else 'unknown)))
        (list (classify 3) (classify 6) (classify 11))
        """
        res = run_string(code, env=env)
        items = [x.name for x in to_py_list(res)]
        assert items == ["odd", "even", "unknown"]


class TestBackendAEquivalence:
    """Validate that Python AST transpiler yields identical results for Phase 2."""

    def test_quasiquote_codegen(self) -> None:
        env = make_initial_env()
        code = "`(1 ,(+ 10 20) ,@'(30 40) 50)"
        interp_res = run_string(code, env=env, backend="interp")
        ast_res = run_string(code, env=env, backend="py_ast")
        assert to_py_list(interp_res) == to_py_list(ast_res)
        assert to_py_list(ast_res) == [1, 30, 30, 40, 50]

    def test_vector_codegen(self) -> None:
        env = make_initial_env()
        code = """
        (define v #(1 2 3))
        (vector-set! v 0 100)
        (vector-ref v 0)
        """
        assert run_string(code, env=env, backend="py_ast") == 100

    def test_guard_codegen(self) -> None:
        env = make_initial_env()
        code = """
        (guard (e ((= e 42) "caught")
                  (else "missed"))
          (raise 42))
        """
        assert run_string(code, env=env, backend="py_ast") == "caught"

    def test_let_values_codegen(self) -> None:
        env = make_initial_env()
        code = """
        (let-values (((x y) (values 5 6)))
          (* x y))
        """
        assert run_string(code, env=env, backend="py_ast") == 30
