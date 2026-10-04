"""Tests for R7RS 6.2.6 & 7.1.1 (scheme inexact) transcendental math functions in ILISP."""

import cmath
import math
from typing import Any

from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all


def eval_code(code: str) -> Any:
    env = make_initial_env(preload_stdlib=True)
    exprs = read_all(code)
    result = None
    for expr in exprs:
        result = eval_expr(expr, env)
    return result


def test_trigonometric_functions_real() -> None:
    """Test sin, cos, tan, asin, acos, atan on real numbers."""
    # Pythagorean identity: sin^2(0.5) + cos^2(0.5) ~ 1.0
    res = eval_code("(+ (* (sin 0.5) (sin 0.5)) (* (cos 0.5) (cos 0.5)))")
    assert math.isclose(float(res), 1.0, rel_tol=1e-9)

    # tan(0.5) ~ sin(0.5) / cos(0.5)
    res_tan = eval_code("(- (tan 0.5) (/ (sin 0.5) (cos 0.5)))")
    assert math.isclose(float(res_tan), 0.0, abs_tol=1e-9)

    # asin(sin(0.3)) ~ 0.3
    res_asin = eval_code("(asin (sin 0.3))")
    assert math.isclose(float(res_asin), 0.3, rel_tol=1e-9)

    # acos(cos(0.7)) ~ 0.7
    res_acos = eval_code("(acos (cos 0.7))")
    assert math.isclose(float(res_acos), 0.7, rel_tol=1e-9)

    # atan(tan(0.4)) ~ 0.4
    res_atan = eval_code("(atan (tan 0.4))")
    assert math.isclose(float(res_atan), 0.4, rel_tol=1e-9)


def test_atan_two_arguments() -> None:
    """Test 2-argument atan(y, x) across all four quadrants."""
    pi = math.pi
    # Quadrant 1: (1, 1) -> pi/4
    assert math.isclose(float(eval_code("(atan 1 1)")), pi / 4, rel_tol=1e-9)
    # Quadrant 2: (1, -1) -> 3*pi/4
    assert math.isclose(float(eval_code("(atan 1 -1)")), 3 * pi / 4, rel_tol=1e-9)
    # Quadrant 3: (-1, -1) -> -3*pi/4
    assert math.isclose(float(eval_code("(atan -1 -1)")), -3 * pi / 4, rel_tol=1e-9)
    # Quadrant 4: (-1, 1) -> -pi/4
    assert math.isclose(float(eval_code("(atan -1 1)")), -pi / 4, rel_tol=1e-9)


def test_exponential_and_logarithms() -> None:
    """Test exp and 1-arg / 2-arg log."""
    # exp(0) == 1.0
    assert math.isclose(float(eval_code("(exp 0)")), 1.0, rel_tol=1e-9)

    # log(exp(3.5)) ~ 3.5
    assert math.isclose(float(eval_code("(log (exp 3.5))")), 3.5, rel_tol=1e-9)

    # 2-argument log: (log 8 2) -> 3.0
    assert math.isclose(float(eval_code("(log 8 2)")), 3.0, rel_tol=1e-9)

    # 2-argument log: (log 1000 10) -> 3.0
    assert math.isclose(float(eval_code("(log 1000 10)")), 3.0, rel_tol=1e-9)


def test_sqrt_extended_domain() -> None:
    """Test sqrt on exact squares, non-squares, and negative / complex numbers."""
    # Exact square integer
    assert eval_code("(sqrt 25)") == 5
    assert eval_code("(sqrt 0)") == 0

    # Non-square float
    res_2 = eval_code("(sqrt 2)")
    assert math.isclose(float(res_2), math.sqrt(2), rel_tol=1e-9)

    # Negative number produces complex
    res_neg = eval_code("(sqrt -4)")
    assert isinstance(res_neg, complex)
    assert math.isclose(res_neg.real, 0.0, abs_tol=1e-9)
    assert math.isclose(res_neg.imag, 2.0, rel_tol=1e-9)

    # Complex number sqrt
    res_c = eval_code("(sqrt (make-rectangular 0 4))")
    expected = cmath.sqrt(4j)
    assert isinstance(res_c, complex)
    assert math.isclose(res_c.real, expected.real, rel_tol=1e-9)
    assert math.isclose(res_c.imag, expected.imag, rel_tol=1e-9)


def test_euler_formula_complex() -> None:
    """Test Euler's identity: e^(i*pi) + 1 ~ 0."""
    code = """
    (define pi (* 4 (atan 1 1)))
    (define i (make-rectangular 0 1))
    (+ (exp (* i pi)) 1)
    """
    res = eval_code(code)
    assert isinstance(res, complex)
    assert abs(res) < 1e-9


def test_predicates_on_complex_and_floats() -> None:
    """Test finite?, infinite?, nan? on floats and complex numbers."""
    assert eval_code("(finite? 42)") is True
    assert eval_code("(finite? (make-rectangular 1.5 -2.5))") is True
    assert eval_code("(finite? (/ 1.0 0.0))") is False

    assert eval_code("(infinite? (/ 1.0 0.0))") is True
    assert eval_code("(infinite? (make-rectangular (/ 1.0 0.0) 2.0))") is True
    assert eval_code("(infinite? 42)") is False

    assert eval_code("(nan? (/ 0.0 0.0))") is True
    assert eval_code("(nan? (make-rectangular 1.0 (/ 0.0 0.0)))") is True
    assert eval_code("(nan? 42)") is False


def test_scheme_inexact_library_import() -> None:
    """Test importing (scheme inexact) library."""
    code = """
    (import (scheme inexact))
    (list (sin 0) (cos 0) (exp 0) (sqrt 9))
    """
    res = eval_code(code)
    from ilisp.types import to_py_list

    assert to_py_list(res) == [0.0, 1.0, 1.0, 3]


def test_scheme_inexact_prefix_import() -> None:
    """Test importing with prefix modifier."""
    code = """
    (import (prefix (scheme inexact) math:))
    (math:log 100 10)
    """
    res = eval_code(code)
    assert math.isclose(float(res), 2.0, rel_tol=1e-9)
