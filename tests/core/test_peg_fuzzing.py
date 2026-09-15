"""Fuzzing and adversarial boundary tests for Packrat PEG parser runtime (Issue #307).

Tests stack depth limits, catastrophic backtracking resistance (ReDoS mitigation),
and resilience against malformed inputs.
"""

import time

import pytest

from src.core.structures.peg import (
    Choice,
    Literal,
    OneOrMore,
    ParseContext,
    PEGSyntaxError,
    RuleRef,
    Sequence,
    ZeroOrMore,
)


def test_deep_nesting_stack_resistance() -> None:
    """Tests parser resilience against deeply nested parentheses within recursion limit."""
    # E <- '(' E ')' / 'x'
    e = RuleRef("E")
    inner = (Literal("(") + e + Literal(")")).map(lambda r: f"({r[1]})")
    base = Literal("x")
    e.define(Choice(inner, base))

    depth = 50  # Safe depth for recursive AST build
    nested_input = "(" * depth + "x" + ")" * depth
    res = e.parse(nested_input)
    assert res == nested_input

    # Malformed (unbalanced) deep nesting raises syntax error gracefully without crash
    unbalanced_input = "(" * depth + "x" + ")" * (depth - 1)
    with pytest.raises(PEGSyntaxError) as excinfo:
        e.parse(unbalanced_input)
    assert excinfo.value.hint is not None or ")" in excinfo.value.expected_tokens


def test_redos_linear_time_guarantee() -> None:
    """Verifies that Packrat memoization and Cut prevents catastrophic backtracking (O(N) guarantee)."""
    # Classical catastrophic pattern in regex: (a+)+$
    # In PEG with Packrat memoization, this evaluates in linear time without exponential blowup.
    a_plus = OneOrMore(Literal("a"))
    expr = Sequence(OneOrMore(a_plus), Literal("b"))

    for n in [100, 300, 500]:
        payload = "a" * n  # Missing trailing 'b', forces full exploration
        ctx = ParseContext(payload)

        start = time.perf_counter()
        res = expr._eval_cached(ctx, 0)
        elapsed = time.perf_counter() - start

        assert res.success is False
        # Packrat PEG must complete well under 0.2 seconds (no exponential blowup)
        assert elapsed < 0.2, f"Backtracking took too long: {elapsed:.4f}s for n={n}"


def test_cut_operator_pruning_performance() -> None:
    """Verifies that Cut operator prevents redundant backtracking attempts on fail."""
    # Choice: ('IF' ^ condition 'THEN' stmt) / ('IF' other)
    # Once 'IF' is seen and cut committed, second choice is never explored.
    branch1 = Literal("IF") ^ Sequence(Literal(" "), Literal("cond"), Literal(" THEN"))
    branch2 = Sequence(Literal("IF"), Literal(" other"))
    p = Choice(branch1, branch2)

    ctx = ParseContext("IF invalid")
    res = p._eval_cached(ctx, 0)
    assert res.success is False
    assert res.committed is True  # Committed failure from Cut


def test_large_token_payload() -> None:
    """Verifies parser handles large token stream within max_input_length."""
    large_text = "a" * 30_000
    p = OneOrMore(Literal("a"))
    ctx = ParseContext(large_text)
    res = p._eval_cached(ctx, 0)
    assert res.success is True
    assert res.next_pos == 30_000


def test_fuzz_random_adversarial_chars() -> None:
    """Fuzzes parser with control characters, null bytes, and non-ASCII sequences."""
    p = ZeroOrMore(
        Choice(Literal("SELECT"), Literal("FROM"), Literal("WHERE"), Literal(" "))
    )
    payload = "SELECT \x00\xff\xfe\x01 FROM \r\n\t WHERE \x7f"
    ctx = ParseContext(payload)
    res = p._eval_cached(ctx, 0)
    # Gracefully matches prefix and stops on unknown byte without crashing
    assert res.success is True
