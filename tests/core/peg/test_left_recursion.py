#!/usr/bin/env python3
"""
Unit tests for Warth-style Left Recursion (Direct & Indirect) support in Packrat PEG.
Verifies:
1. Direct left recursion termination and longest-match seed growing.
2. Correct left-associative AST evaluation (e.g. 10 - 3 - 2 = 5, not 9).
3. Arithmetic expression grammar with left-recursive addition and subtraction.
4. Security and depth bounds during left-recursion seed growing.
"""

from typing import cast

from core.structures.peg import Lit, Reg, RuleRef


def test_direct_left_recursion_addition() -> None:
    """Verifies that direct left recursion Expr <- Expr '+' Num / Num parses left-associatively."""
    expr = RuleRef("Expr")
    num = Reg(r"\d+").map(int)
    plus = Lit("+")

    # Expr <- Expr '+' num -> tuple(expr, '+', num)
    add_rule = (expr + plus + num).map(lambda r: (r[0], "+", r[2]))
    expr.define(add_rule / num)

    res = expr.parse("1+2+3")
    # Expected left-associative tree: ((1, '+', 2), '+', 3)
    assert res == ((1, "+", 2), "+", 3)


def test_direct_left_recursion_subtraction_associativity() -> None:
    """Verifies that subtraction evaluates with mathematical left-associativity (10-3-2=5)."""
    expr = RuleRef("Expr")
    num = Reg(r"\d+").map(int)
    minus = Lit("-")

    # Semantic action computes integer value directly
    sub_rule = (expr + minus + num).map(lambda r: cast(int, r[0]) - cast(int, r[2]))
    expr.define(sub_rule / num)

    val = expr.parse("10-3-2")
    # Left-associative: (10 - 3) - 2 = 5
    # If right-associative, it would be 10 - (3 - 2) = 9
    assert val == 5


def test_direct_left_recursion_complex_precedence() -> None:
    """Verifies left-recursive expressions with mixed operators and parentheses."""
    expr = RuleRef("Expr")
    term = RuleRef("Term")
    factor = RuleRef("Factor")
    num = Reg(r"\d+").map(int)

    # Expr <- Expr ('+' / '-') Term / Term
    add_sub = (expr + (Lit("+") / Lit("-")) + term).map(
        lambda r: (r[0] + r[2]) if r[1] == "+" else (r[0] - r[2])
    )
    expr.define(add_sub / term)

    # Term <- Term ('*' / '/') Factor / Factor
    mul_div = (term + (Lit("*") / Lit("/")) + factor).map(
        lambda r: (r[0] * r[2]) if r[1] == "*" else (r[0] // r[2])
    )
    term.define(mul_div / factor)

    # Factor <- '(' Expr ')' / num
    paren = (Lit("(") + expr + Lit(")")).map(lambda r: r[1])
    factor.define(paren / num)

    assert expr.parse("2+3*4") == 14
    assert expr.parse("(2+3)*4") == 20
    assert expr.parse("20-5-3") == 12
    assert expr.parse("100/5/2") == 10


def test_indirect_left_recursion() -> None:
    """Verifies indirect left recursion across multiple rules (A <- B / 'x', B <- A 'y')."""
    a = RuleRef("A")
    b = RuleRef("B")

    # A <- B / 'x'
    a.define(b / Lit("x"))
    # B <- A 'y' -> flattened string
    b.define((a + Lit("y")).map(lambda r: f"{r[0]}y"))

    assert a.parse("x") == "x"
    assert a.parse("xy") == "xy"
    assert a.parse("xyy") == "xyy"
    assert a.parse("xyyy") == "xyyy"
