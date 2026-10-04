"""Tests for R7RS Type Predicates (boolean=?, symbol=?) and syntax-error."""

from typing import Any

import pytest

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import ErrorObject, SchemeException, is_read_error


def eval_str(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


class TestBooleanEq:
    """Tests for R7RS 6.3 boolean=?"""

    def test_boolean_eq_two_args_true(self) -> None:
        assert eval_str("(boolean=? #t #t)") is True
        assert eval_str("(boolean=? #f #f)") is True

    def test_boolean_eq_two_args_false(self) -> None:
        assert eval_str("(boolean=? #t #f)") is False
        assert eval_str("(boolean=? #f #t)") is False

    def test_boolean_eq_multi_args(self) -> None:
        assert eval_str("(boolean=? #t #t #t #t)") is True
        assert eval_str("(boolean=? #f #f #f #f #f)") is True
        assert eval_str("(boolean=? #t #t #f #t)") is False
        assert eval_str("(boolean=? #f #f #f #t)") is False

    def test_boolean_eq_type_error(self) -> None:
        with pytest.raises(Exception):
            eval_str("(boolean=? #t 1)")
        with pytest.raises(Exception):
            eval_str('(boolean=? "true" "true")')
        with pytest.raises(Exception):
            eval_str("(boolean=? '() '())")

    def test_boolean_eq_arity_error(self) -> None:
        with pytest.raises(Exception):
            eval_str("(boolean=?)")
        with pytest.raises(Exception):
            eval_str("(boolean=? #t)")


class TestSymbolEq:
    """Tests for R7RS 6.5 symbol=?"""

    def test_symbol_eq_two_args_true(self) -> None:
        assert eval_str("(symbol=? 'foo 'foo)") is True
        assert eval_str("(symbol=? 'hello 'hello)") is True

    def test_symbol_eq_two_args_false(self) -> None:
        assert eval_str("(symbol=? 'foo 'bar)") is False
        assert eval_str("(symbol=? 'a 'b)") is False

    def test_symbol_eq_multi_args(self) -> None:
        assert eval_str("(symbol=? 'x 'x 'x)") is True
        assert eval_str("(symbol=? 'x 'x 'y)") is False
        assert eval_str("(symbol=? 'alpha 'alpha 'alpha 'alpha)") is True
        assert eval_str("(symbol=? 'alpha 'alpha 'beta 'alpha)") is False

    def test_symbol_eq_type_error(self) -> None:
        with pytest.raises(Exception):
            eval_str('(symbol=? \'foo "foo")')
        with pytest.raises(Exception):
            eval_str("(symbol=? 10 10)")
        with pytest.raises(Exception):
            eval_str("(symbol=? #t #t)")

    def test_symbol_eq_arity_error(self) -> None:
        with pytest.raises(Exception):
            eval_str("(symbol=?)")
        with pytest.raises(Exception):
            eval_str("(symbol=? 'foo)")


class TestSyntaxError:
    """Tests for R7RS 4.3.1 syntax-error"""

    def test_syntax_error_direct_raise(self) -> None:
        with pytest.raises(SchemeException) as excinfo:
            eval_str('(syntax-error "invalid syntax")')
        err = excinfo.value.datum
        assert isinstance(err, ErrorObject)
        assert is_read_error(err)
        assert err.message == "invalid syntax"

    def test_syntax_error_with_irritants(self) -> None:
        code = """
        (guard (e ((read-error? e)
                   (list (error-object-message e)
                         (car (error-object-irritants e)))))
          (syntax-error "unsupported operand" foo))
        """
        res = eval_str(code)
        # res should be a Scheme list: ("unsupported operand" foo)
        from ilisp.types import to_py_list

        py_list = to_py_list(res)
        assert py_list[0] == "unsupported operand"
        assert str(py_list[1]) == "foo"

    def test_syntax_error_in_macro(self) -> None:
        code = """
        (define-syntax my-strict-add
          (syntax-rules ()
            ((my-strict-add a b) (+ a b))
            ((my-strict-add a) (syntax-error "my-strict-add requires 2 arguments" a))))
        (my-strict-add 10 20)
        """
        assert eval_str(code) == 30

        code_fail = """
        (define-syntax my-strict-add
          (syntax-rules ()
            ((my-strict-add a b) (+ a b))
            ((my-strict-add a) (syntax-error "my-strict-add requires 2 arguments" a))))
        (guard (e ((read-error? e) (error-object-message e)))
          (my-strict-add 10))
        """
        assert eval_str(code_fail) == "my-strict-add requires 2 arguments"

    def test_syntax_error_procedure_call(self) -> None:
        code = """
        (guard (e ((error-object? e) (error-object-message e)))
          (apply syntax-error '("bad form" 1 2)))
        """
        assert eval_str(code) == "bad form"
