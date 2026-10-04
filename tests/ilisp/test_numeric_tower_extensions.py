"""Tests for R7RS 6.2 Numbers extensions: exact-integer-sqrt and (scheme complex)."""

import math
from typing import Any

import pytest

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all
from ilisp.types import to_py_list


def eval_str(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


class TestExactIntegerSqrt:
    """Tests for exact-integer-sqrt."""

    def test_exact_integer_sqrt_zero(self) -> None:
        code = """
        (let-values (((s r) (exact-integer-sqrt 0)))
          (list s r))
        """
        assert to_py_list(eval_str(code)) == [0, 0]

    def test_exact_integer_sqrt_perfect_square(self) -> None:
        code = """
        (let-values (((s r) (exact-integer-sqrt 16)))
          (list s r))
        """
        assert to_py_list(eval_str(code)) == [4, 0]

    def test_exact_integer_sqrt_non_perfect(self) -> None:
        code = """
        (let-values (((s r) (exact-integer-sqrt 17)))
          (list s r))
        """
        assert to_py_list(eval_str(code)) == [4, 1]

        code_large = """
        (let-values (((s r) (exact-integer-sqrt 1000)))
          (list s r (= (+ (* s s) r) 1000)))
        """
        assert to_py_list(eval_str(code_large)) == [31, 39, True]

    def test_exact_integer_sqrt_error(self) -> None:
        with pytest.raises(Exception):
            eval_str("(exact-integer-sqrt -1)")
        with pytest.raises(Exception):
            eval_str("(exact-integer-sqrt 3.14)")
        with pytest.raises(Exception):
            eval_str('(exact-integer-sqrt "16")')


class TestComplexNumbers:
    """Tests for complex?, real?, rational?, make-rectangular, make-polar, etc."""

    def test_complex_predicate(self) -> None:
        assert eval_str("(complex? 123)") is True
        assert eval_str("(complex? 3.14)") is True
        assert eval_str("(complex? (make-rectangular 1 2))") is True
        assert eval_str("(complex? (make-polar 2 0))") is True
        assert eval_str('(complex? "123")') is False
        assert eval_str("(complex? '())") is False

    def test_real_and_rational_with_complex(self) -> None:
        assert eval_str("(real? (make-rectangular 5 0))") is True
        assert eval_str("(real? (make-rectangular 5 2))") is False
        assert eval_str("(rational? (make-rectangular 5 0))") is True
        assert eval_str("(rational? (make-rectangular 5 2))") is False

    def test_make_rectangular_and_accessors(self) -> None:
        code = """
        (let ((z (make-rectangular 3.0 4.0)))
          (list (real-part z) (imag-part z) (magnitude z)))
        """
        res = to_py_list(eval_str(code))
        assert res[0] == 3.0
        assert res[1] == 4.0
        assert math.isclose(res[2], 5.0)

    def test_make_polar_and_angle(self) -> None:
        code = """
        (let ((z (make-polar 5.0 0.0)))
          (list (magnitude z) (angle z)))
        """
        res = to_py_list(eval_str(code))
        assert math.isclose(res[0], 5.0)
        assert math.isclose(res[1], 0.0)

    def test_real_imag_part_on_reals(self) -> None:
        assert eval_str("(real-part 42)") == 42
        assert eval_str("(imag-part 42)") == 0
        assert eval_str("(magnitude -10)") == 10

    def test_complex_arithmetic(self) -> None:
        code_add = "(+ (make-rectangular 1 2) (make-rectangular 3 4))"
        z_add = eval_str(code_add)
        assert isinstance(z_add, complex)
        assert z_add.real == 4.0
        assert z_add.imag == 6.0

        code_mul = "(* (make-rectangular 1 2) (make-rectangular 1 -2))"
        z_mul = eval_str(code_mul)
        assert z_mul.real == 5.0
        assert z_mul.imag == 0.0

    def test_complex_eqv(self) -> None:
        code = "(eqv? (make-rectangular 1 2) (make-rectangular 1 2))"
        assert eval_str(code) is True
        code_diff = "(eqv? (make-rectangular 1 2) (make-rectangular 1 3))"
        assert eval_str(code_diff) is False
