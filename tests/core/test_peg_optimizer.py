"""Tests for PEG AOT compiler AST optimizer passes (Issue #305)."""

from src.core.structures.peg_compiler.ast_nodes import (
    ChoiceExpr,
    GrammarDef,
    LitExpr,
    RuleDef,
    SeqExpr,
)
from src.core.structures.peg_compiler.optimizer import GrammarOptimizer


def test_literal_folding() -> None:
    """Test consecutive literals in a sequence are folded into one."""
    optimizer = GrammarOptimizer()
    # Sequence of "foo", "bar", "baz" -> "foobarbaz"
    rule = RuleDef(
        name="test_rule",
        expr=SeqExpr(
            elements=[
                LitExpr("foo"),
                LitExpr("bar"),
                LitExpr("baz"),
            ]
        ),
    )
    grammar = GrammarDef(name="test_grammar", rules=[rule])
    opt_grammar = optimizer.optimize_grammar(grammar)

    opt_rule = opt_grammar.rules[0]
    assert isinstance(opt_rule.expr, LitExpr)
    assert opt_rule.expr.value == "foobarbaz"


def test_left_factoring() -> None:
    """Test common prefix expressions in Choice branches are factored out."""
    from src.core.structures.peg_compiler.ast_nodes import RuleRefExpr

    optimizer = GrammarOptimizer()
    # Choice of "SELECT" all_clause, "SELECT" distinct_clause -> "SELECT" (all_clause / distinct_clause)
    rule = RuleDef(
        name="select_stmt",
        expr=ChoiceExpr(
            alternatives=[
                SeqExpr([LitExpr("SELECT"), RuleRefExpr("all_clause")]),
                SeqExpr([LitExpr("SELECT"), RuleRefExpr("distinct_clause")]),
            ]
        ),
    )
    grammar = GrammarDef(name="test_grammar", rules=[rule])
    opt_grammar = optimizer.optimize_grammar(grammar)

    opt_rule = opt_grammar.rules[0]
    assert isinstance(opt_rule.expr, SeqExpr)
    assert len(opt_rule.expr.elements) == 2
    prefix = opt_rule.expr.elements[0]
    suffix = opt_rule.expr.elements[1]
    assert isinstance(prefix, LitExpr)
    assert prefix.value == "SELECT"
    assert isinstance(suffix, ChoiceExpr)
    assert len(suffix.alternatives) == 2
    assert suffix.alternatives[0] == RuleRefExpr("all_clause")
    assert suffix.alternatives[1] == RuleRefExpr("distinct_clause")


def test_redundancy_pruning() -> None:
    """Test single-element Sequence and Choice are pruned/unwrapped."""
    optimizer = GrammarOptimizer()
    rule = RuleDef(
        name="single_choice",
        expr=ChoiceExpr(
            alternatives=[
                SeqExpr(
                    elements=[
                        LitExpr("hello"),
                    ]
                )
            ]
        ),
    )
    grammar = GrammarDef(name="test_grammar", rules=[rule])
    opt_grammar = optimizer.optimize_grammar(grammar)

    opt_rule = opt_grammar.rules[0]
    assert isinstance(opt_rule.expr, LitExpr)
    assert opt_rule.expr.value == "hello"
