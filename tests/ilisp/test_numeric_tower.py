"""Test Suite for R7RS Section 6.2 Numbers and Arithmetic in ILISP.

Tests numerical predicates, rounding, integer division variants,
min/max/abs, gcd/lcm, radix-aware number/string conversions, and Backend A integration.
"""

from __future__ import annotations

import math
from typing import Any

import pytest

from ilisp.backend.py_codegen.compiler import compile_ilisp
from ilisp.env import make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import read_all


def run_code(code: str) -> Any:
    env = make_initial_env()
    res = None
    for expr in read_all(code):
        res = eval_expr(expr, env)
    return res


class TestBasicArithmeticAndDivision:
    """Tests basic arithmetic and multi-argument division."""

    def test_division(self) -> None:
        assert run_code("(/ 2)") == 0.5
        assert run_code("(/ 1)") == 1
        assert run_code("(/ -1)") == -1
        assert run_code("(/ 12 2 3)") == 2
        assert run_code("(/ 10 4)") == 2.5

    def test_division_by_zero(self) -> None:
        with pytest.raises(ZeroDivisionError):
            run_code("(/ 1 0)")


class TestComparisonPredicates:
    """Tests multi-argument numerical comparisons (=, <, >, <=, >=)."""

    def test_equality(self) -> None:
        assert run_code("(= 5 5 5)") is True
        assert run_code("(= 5 5 6)") is False
        assert run_code("(= 5)") is True

    def test_inequalities(self) -> None:
        assert run_code("(< 1 2 3 4)") is True
        assert run_code("(< 1 2 2 4)") is False
        assert run_code("(<= 1 2 2 4)") is True
        assert run_code("(> 4 3 2 1)") is True
        assert run_code("(>= 4 3 3 1)") is True
        assert run_code("(>= 4 3 5 1)") is False


class TestNumericalPredicates:
    """Tests exactness, integer, finite, and sign predicates."""

    def test_exactness(self) -> None:
        assert run_code("(exact? 42)") is True
        assert run_code("(exact? 42.0)") is False
        assert run_code("(inexact? 42.0)") is True
        assert run_code("(inexact? 42)") is False
        assert run_code("(exact-integer? 42)") is True
        assert run_code("(exact-integer? 42.0)") is False

    def test_type_predicates(self) -> None:
        assert run_code("(number? 100)") is True
        assert run_code("(number? 3.14)") is True
        assert run_code("(number? #t)") is False
        assert run_code('(number? "100")') is False
        assert run_code("(integer? 42)") is True
        assert run_code("(integer? 42.0)") is True
        assert run_code("(integer? 42.5)") is False

    def test_sign_and_parity(self) -> None:
        assert run_code("(zero? 0)") is True
        assert run_code("(zero? 1)") is False
        assert run_code("(positive? 5)") is True
        assert run_code("(positive? -5)") is False
        assert run_code("(positive? 0)") is False
        assert run_code("(negative? -5)") is True
        assert run_code("(negative? 5)") is False
        assert run_code("(odd? 3)") is True
        assert run_code("(odd? 4)") is False
        assert run_code("(even? 4)") is True
        assert run_code("(even? 3)") is False


class TestRoundingAndExtremes:
    """Tests floor, ceiling, truncate, round, min, max, abs, gcd, lcm."""

    def test_rounding_functions(self) -> None:
        assert run_code("(floor 3.7)") == 3.0
        assert run_code("(floor -3.7)") == -4.0
        assert run_code("(ceiling 3.2)") == 4.0
        assert run_code("(ceiling -3.2)") == -3.0
        assert run_code("(truncate 3.7)") == 3.0
        assert run_code("(truncate -3.7)") == -3.0
        assert run_code("(round 3.5)") == 4.0
        assert run_code("(round 2.5)") == 2.0  # Round to even

    def test_extremes_and_abs(self) -> None:
        assert run_code("(max 3 1 4 1 5 9 2)") == 9
        assert run_code("(min 3 1 4 1 5 9 2)") == 1
        assert run_code("(max 3 5.0)") == 5.0  # Preserve inexactness
        assert isinstance(run_code("(max 3 5.0)"), float)
        assert run_code("(abs -42)") == 42
        assert run_code("(abs 42.5)") == 42.5

    def test_gcd_and_lcm(self) -> None:
        assert run_code("(gcd)") == 0
        assert run_code("(gcd 12 18 24)") == 6
        assert run_code("(lcm)") == 1
        assert run_code("(lcm 4 6 8)") == 24
        assert run_code("(lcm 4 0 8)") == 0


class TestIntegerDivisionVariants:
    """Tests floor/, truncate/, quotient, remainder, and modulo."""

    def test_quotient_and_remainder(self) -> None:
        assert run_code("(quotient 13 4)") == 3
        assert run_code("(quotient -13 4)") == -3
        assert run_code("(remainder 13 4)") == 1
        assert run_code("(remainder -13 4)") == -1
        assert run_code("(modulo 13 4)") == 1
        assert run_code("(modulo -13 4)") == 3

    def test_floor_and_truncate_div(self) -> None:
        res = run_code("(let-values (((q r) (floor/ -13 4))) (list q r))")
        assert res.car == -4
        assert res.cdr.car == 3

        res2 = run_code("(let-values (((q r) (truncate/ -13 4))) (list q r))")
        assert res2.car == -3
        assert res2.cdr.car == -1


class TestPowersAndRoots:
    """Tests square, sqrt, and expt."""

    def test_powers(self) -> None:
        assert run_code("(square 5)") == 25
        assert run_code("(square -3)") == 9
        assert run_code("(sqrt 16)") == 4
        assert run_code("(sqrt 2)") == pytest.approx(math.sqrt(2))
        assert run_code("(expt 2 10)") == 1024
        assert run_code("(expt 2 -1)") == 0.5


class TestRadixAndStringConversions:
    """Tests number->string and string->number with base 2, 8, 10, 16."""

    def test_number_to_string(self) -> None:
        assert run_code("(number->string 255 16)") == "ff"
        assert run_code("(number->string 255 10)") == "255"
        assert run_code("(number->string 255 8)") == "377"
        assert run_code("(number->string 255 2)") == "11111111"
        assert run_code("(number->string -42 16)") == "-2a"

    def test_string_to_number(self) -> None:
        assert run_code('(string->number "255")') == 255
        assert run_code('(string->number "ff" 16)') == 255
        assert run_code('(string->number "#xff")') == 255
        assert run_code('(string->number "#b1010")') == 10
        assert run_code('(string->number "#o77")') == 63
        assert run_code('(string->number "3.14")') == 3.14
        assert run_code('(string->number "not-a-number")') is False
        assert run_code('(string->number "123" 2)') is False  # Invalid binary string


class TestBackendANumericIntegration:
    """Tests that Backend A (Python AST transpiler) compiles numeric expressions correctly."""

    def test_py_codegen_numeric(self) -> None:
        code = """
        (define (hypot a b)
          (sqrt (+ (square a) (square b))))

        (define val (hypot 3 4))
        (list val (odd? (floor val)) (number->string val 10))
        """
        res = compile_ilisp(code)
        assert res.car == 5
        assert res.cdr.car is True  # 5 is odd
        assert res.cdr.cdr.car == "5"
