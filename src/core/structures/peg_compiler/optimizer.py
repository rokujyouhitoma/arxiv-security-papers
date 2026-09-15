#!/usr/bin/env python3
"""
AST Optimization passes for PEG Grammar Specifications.
Applies:
1. Constant folding: combines adjacent literal matches (Lit('a') + Lit('b') -> Lit('ab')).
2. Common prefix left-factoring: A B / A C -> A (B / C).
3. Redundancy pruning: eliminates single-element choices/sequences and empty literals.
Conforms to DSN-25 PEG Optimization specification.
"""

from __future__ import annotations

from typing import List, Optional

from .ast_nodes import (
    ActionExpr,
    ChoiceExpr,
    Expression,
    GrammarDef,
    LitExpr,
    NamedExpr,
    OptExpr,
    PredExpr,
    RepeatExpr,
    RuleDef,
    SeqExpr,
)


def _fold_literals(elements: List[Expression]) -> List[Expression]:
    """Combines adjacent string literal match nodes into a single literal."""
    folded: List[Expression] = []
    curr_lit: str = ""

    for elem in elements:
        if isinstance(elem, LitExpr):
            curr_lit += elem.value
        else:
            if curr_lit:
                folded.append(LitExpr(curr_lit))
                curr_lit = ""
            folded.append(elem)

    if curr_lit:
        folded.append(LitExpr(curr_lit))
    return folded


def _prune_seq_elements(elements: List[Expression]) -> List[Expression]:
    """Removes empty epsilon literals unless the sequence would become completely empty."""
    pruned = [e for e in elements if not (isinstance(e, LitExpr) and e.value == "")]
    return pruned if pruned else [LitExpr("")]


def _extract_head_tail(elem: Expression) -> tuple[Expression, Expression]:
    """Extracts first element and remainder for left-factoring."""
    if isinstance(elem, SeqExpr) and len(elem.elements) > 1:
        tail = (
            elem.elements[1]
            if len(elem.elements) == 2
            else SeqExpr(list(elem.elements[1:]))
        )
        return elem.elements[0], tail
    return elem, LitExpr("")


def _collect_common_head_tails(
    head_i: Expression, alts: List[Expression], start_j: int
) -> tuple[List[Expression], int]:
    matched_tails: List[Expression] = []
    j = start_j
    n = len(alts)
    while j < n:
        head_j, tail_j = _extract_head_tail(alts[j])
        if head_j != head_i:
            break
        matched_tails.append(tail_j)
        j += 1
    return matched_tails, j


def _factor_alternatives(alts: List[Expression]) -> List[Expression]:
    """Applies left-factoring to choices with identical leading expressions."""
    if len(alts) < 2:
        return alts

    factored: List[Expression] = []
    i = 0
    n = len(alts)
    while i < n:
        head_i, tail_i = _extract_head_tail(alts[i])
        tails, j = _collect_common_head_tails(head_i, alts, i + 1)
        if tails:
            factored.append(SeqExpr([head_i, ChoiceExpr([tail_i] + tails)]))
            i = j
        else:
            factored.append(alts[i])
            i += 1
    return factored


class GrammarOptimizer:
    """Performs static optimization passes on PEG GrammarDef ASTs."""

    def optimize_grammar(self, grammar: GrammarDef) -> GrammarDef:
        """Optimizes all rule expressions within the grammar."""
        opt_rules: List[RuleDef] = []
        for r in grammar.rules:
            opt_expr = self.optimize_expression(r.expr)
            opt_rules.append(RuleDef(name=r.name, expr=opt_expr, docstring=r.docstring))
        return GrammarDef(
            name=grammar.name,
            rules=opt_rules,
            header_code=grammar.header_code,
            start_rule=grammar.start_rule,
        )

    def _optimize_composite(self, expr: Expression) -> Optional[Expression]:
        if isinstance(expr, SeqExpr):
            return self._optimize_seq(expr)
        if isinstance(expr, ChoiceExpr):
            return self._optimize_choice(expr)
        return None

    def _optimize_unary(self, expr: Expression) -> Optional[Expression]:
        if isinstance(expr, RepeatExpr):
            return RepeatExpr(
                self.optimize_expression(expr.expr), expr.min_count, expr.max_count
            )
        if isinstance(expr, OptExpr):
            return OptExpr(self.optimize_expression(expr.expr))
        if isinstance(expr, PredExpr):
            return PredExpr(self.optimize_expression(expr.expr), expr.is_positive)
        return None

    def _optimize_annotated(self, expr: Expression) -> Optional[Expression]:
        if isinstance(expr, NamedExpr):
            return NamedExpr(expr.name, self.optimize_expression(expr.expr))
        if isinstance(expr, ActionExpr):
            return ActionExpr(self.optimize_expression(expr.expr), expr.action_code)
        return None

    def optimize_expression(self, expr: Expression) -> Expression:
        """Recursively transforms and optimizes parsing expressions."""
        opt = (
            self._optimize_composite(expr)
            or self._optimize_unary(expr)
            or self._optimize_annotated(expr)
        )
        return opt if opt is not None else expr

    def _optimize_seq(self, expr: SeqExpr) -> Expression:
        opt_elements = [self.optimize_expression(e) for e in expr.elements]
        folded = _fold_literals(opt_elements)
        pruned = _prune_seq_elements(folded)
        if len(pruned) == 1:
            return pruned[0]
        return SeqExpr(pruned)

    def _optimize_choice(self, expr: ChoiceExpr) -> Expression:
        opt_alts = [self.optimize_expression(a) for a in expr.alternatives]
        factored = _factor_alternatives(opt_alts)
        if len(factored) == 1:
            return factored[0]
        return ChoiceExpr(factored)
