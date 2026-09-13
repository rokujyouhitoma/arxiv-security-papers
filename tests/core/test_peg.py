#!/usr/bin/env python3
"""
Unit Tests for Pure Python Packrat PEG Parser Engine.
Tests all combinators, semantic actions, mutually recursive grammars,
Packrat linear-time memoization, max-position error tracking, and security guards.
"""

import time
from typing import Any, List, Tuple

import pytest

from core.structures.peg import (
    AndPred,
    Choice,
    Empty,
    Lit,
    NotPred,
    OneOrMore,
    Opt,
    ParseContext,
    PEGSyntaxError,
    Reg,
    RuleRef,
    Seq,
    ZeroOrMore,
)


def test_basic_combinators_literal_and_regex() -> None:
    lit = Lit("SELECT")
    assert lit.parse("SELECT") == "SELECT"
    with pytest.raises(PEGSyntaxError) as exc_info:
        lit.parse("INSERT")
    assert "Expected 'SELECT'" in str(exc_info.value)
    assert exc_info.value.line == 1
    assert exc_info.value.col == 1

    reg = Reg(r"[a-zA-Z_][a-zA-Z0-9_]*")
    assert reg.parse("user_id_123") == "user_id_123"
    with pytest.raises(PEGSyntaxError):
        reg.parse("123_invalid")


def test_empty_combinator() -> None:
    empty = Empty()
    ctx = ParseContext("test")
    res = empty.parse_at(ctx, 0)
    assert res.success
    assert res.value is None
    assert res.next_pos == 0


def test_sequence_and_operators() -> None:
    seq = Lit("a") + Lit("b") + Lit("c")
    assert seq.parse("abc") == ["a", "b", "c"]
    with pytest.raises(PEGSyntaxError) as exc_info:
        seq.parse("abd")
    assert "Expected 'c'" in str(exc_info.value)


def test_choice_and_operators() -> None:
    choice = Lit("cat") / Lit("car") / Lit("cart")
    assert choice.parse("cat") == "cat"
    assert choice.parse("car") == "car"
    # In PEG, "car" matches first before "cart", trailing "t" causes unconsumed error
    with pytest.raises(PEGSyntaxError):
        choice.parse("cart")

    # Correct ordered choice prioritizing longer prefix
    choice_fixed = Lit("cart") / Lit("car")
    assert choice_fixed.parse("cart") == "cart"
    assert choice_fixed.parse("car") == "car"


def test_repetition_zero_or_more_and_one_or_more() -> None:
    zero_or_more = ZeroOrMore(Lit("a"))
    assert zero_or_more.parse("") == []
    assert zero_or_more.parse("a") == ["a"]
    assert zero_or_more.parse("aaaa") == ["a", "a", "a", "a"]

    one_or_more = OneOrMore(Lit("x"))
    assert one_or_more.parse("x") == ["x"]
    assert one_or_more.parse("xxx") == ["x", "x", "x"]
    with pytest.raises(PEGSyntaxError):
        one_or_more.parse("")


def test_optional_combinator() -> None:
    opt = Opt(Lit("https://"), default="http://")
    assert opt.parse("https://") == "https://"
    assert opt.parse("") == "http://"


def test_predicates_and_lookahead() -> None:
    # AndPred (&e): checks match without consuming
    # Rule: &Lit("class") + Reg(r"[a-z]+")
    pred = AndPred(Lit("class")) + Reg(r"[a-z]+")
    res = pred.parse("class")
    assert res == [None, "class"]

    # NotPred (!e): checks non-match without consuming
    # Match an identifier that is NOT a keyword "def"
    ident = Seq(NotPred(Lit("def")), Reg(r"[a-z]+")).map(lambda x: x[1])
    assert ident.parse("abc") == "abc"
    with pytest.raises(PEGSyntaxError):
        ident.parse("def")


def test_semantic_action_map() -> None:
    # Integer parser converting digits to int
    int_parser = Reg(r"\d+").map(int)
    assert int_parser.parse("42") == 42
    assert isinstance(int_parser.parse("100"), int)


def test_mutually_recursive_arithmetic_grammar() -> None:
    # Expr = Term (('+' / '-') Term)*
    # Term = Factor (('*' / '/') Factor)*
    # Factor = '(' Expr ')' / Number
    expr = RuleRef("Expr")
    term = RuleRef("Term")
    factor = RuleRef("Factor")

    number = Reg(r"\d+").map(int)

    def _eval_binary(initial: int, rest: List[Tuple[str, int]]) -> int:
        val = initial
        for op, operand in rest:
            if op == "+":
                val += operand
            elif op == "-":
                val -= operand
            elif op == "*":
                val *= operand
            elif op == "/":
                val //= operand
        return val

    def _eval_expr(val: Any) -> int:
        initial: int = val[0]
        rest: List[Tuple[str, int]] = [(item[0], item[1]) for item in val[1]]
        return _eval_binary(initial, rest)

    factor.define(
        Choice(
            Seq(Lit("("), expr, Lit(")")).map(lambda x: x[1]),
            number,
        )
    )

    term_op = Lit("*") / Lit("/")
    term_rest = ZeroOrMore(Seq(term_op, factor))
    term.define(Seq(factor, term_rest).map(_eval_expr))

    expr_op = Lit("+") / Lit("-")
    expr_rest = ZeroOrMore(Seq(expr_op, term))
    expr.define(Seq(term, expr_rest).map(_eval_expr))

    assert expr.parse("1+2") == 3
    assert expr.parse("2*3+4") == 10
    assert expr.parse("2*(3+4)") == 14
    assert expr.parse("100-20/2") == 90
    assert expr.parse("((1+2)*(3+4))") == 21


def test_syntax_error_reporting_with_line_and_col() -> None:
    grammar = Seq(
        Lit("SELECT"),
        Lit(" "),
        Lit("*"),
        Lit(" "),
        Lit("FROM"),
        Reg(r"\s+"),
        Reg(r"[a-z]+"),
    )
    query = "SELECT * FROM \n  123"
    with pytest.raises(PEGSyntaxError) as exc_info:
        grammar.parse(query)
    err = exc_info.value
    assert err.line == 2
    assert err.col == 3
    assert "123" in err.snippet


def test_packrat_linear_time_scaling() -> None:
    # Highly ambiguous grammar: S = 'a' S 'a' / 'a' S / 'a'
    # Without memoization, this exhibits O(2^N) exponential backtracking.
    # With Packrat memoization, it scales linearly O(N).
    s = RuleRef("S")
    s.define(
        Choice(
            Seq(Lit("a"), s, Lit("a")),
            Seq(Lit("a"), s),
            Lit("a"),
        )
    )

    lengths = [10, 20, 40]
    durations: List[float] = []
    for length in lengths:
        input_str = "a" * length
        start = time.perf_counter()
        res = s.parse(input_str)
        dur = time.perf_counter() - start
        assert res is not None
        durations.append(dur)

    # 40 chars should not explode into seconds
    assert durations[-1] < 0.1, f"Parsing took too long: {durations[-1]}s"


def test_security_guards() -> None:
    # 1. Max input length guard
    parser = Lit("a")
    huge_input = "a" * 70000
    with pytest.raises(ValueError) as exc:
        parser.parse(huge_input)
    assert "exceeds maximum allowed" in str(exc.value)

    # 2. Left recursion / infinite loop guard
    # Construct an infinitely recursive rule: R = R
    inf_ref = RuleRef("Inf")
    inf_ref.define(inf_ref)
    with pytest.raises(PEGSyntaxError) as exc_info:
        inf_ref.parse("a")
    assert "Left recursion or infinite loop detected" in str(exc_info.value)
