#!/usr/bin/env python3
"""
Dynamic Programming (DP) Join Order Enumerator and Optimizer (System R Style).
Explores the exponential space of N-way table joins to find the global minimum cost execution tree.
"""

import enum
import itertools
import math
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from .stats import TableStats


class JoinPhysicalOperator(enum.Enum):
    """Physical join algorithm operators."""

    NESTED_LOOP_JOIN = "NestedLoopJoin"
    HASH_JOIN = "HashJoin"
    INDEX_JOIN = "IndexJoin"


class JoinPlanNode:
    """Represents a node in the physical join execution tree."""

    def __init__(
        self,
        left: Union[str, "JoinPlanNode"],
        right: Union[str, "JoinPlanNode"],
        operator: JoinPhysicalOperator,
        cost: float,
        estimated_rows: int,
        join_condition: Optional[str] = None,
    ) -> None:
        self.left = left
        self.right = right
        self.operator = operator
        self.cost = cost
        self.estimated_rows = estimated_rows
        self.join_condition = join_condition

    def to_dict(self) -> Dict[str, Any]:
        """Serializes join tree into nested dictionary."""
        return {
            "operator": self.operator.value,
            "cost": self.cost,
            "estimated_rows": self.estimated_rows,
            "condition": self.join_condition,
            "left": self.left if isinstance(self.left, str) else self.left.to_dict(),
            "right": (
                self.right if isinstance(self.right, str) else self.right.to_dict()
            ),
        }


def _eval_split_plan(
    s1: List[str],
    s2: List[str],
    dp_table: Dict[frozenset[str], JoinPlanNode],
    conditions: List[Dict[str, str]],
    indexes: Dict[str, Set[str]],
) -> Optional[JoinPlanNode]:
    """Evaluates the join cost between subset 1 and subset 2."""
    s1_fs = frozenset(s1)
    s2_fs = frozenset(s2)

    if s1_fs not in dp_table or s2_fs not in dp_table:
        return None

    left_plan = dp_table[s1_fs]
    right_plan = dp_table[s2_fs]

    cond_str, has_idx = _check_join_link(s1, s2, conditions, indexes)
    sel = 0.1 if cond_str else 1.0
    est_rows = max(1, int(left_plan.estimated_rows * right_plan.estimated_rows * sel))

    op, cost = _estimate_join_cost(
        left_rows=left_plan.estimated_rows,
        left_cost=left_plan.cost,
        right_rows=right_plan.estimated_rows,
        right_cost=right_plan.cost,
        has_index_on_right=has_idx,
    )

    return JoinPlanNode(
        left=left_plan,
        right=right_plan,
        operator=op,
        cost=cost,
        estimated_rows=est_rows,
        join_condition=cond_str,
    )


def _check_join_link(
    s1: List[str],
    s2: List[str],
    conditions: List[Dict[str, str]],
    indexes: Dict[str, Set[str]],
) -> Tuple[Optional[str], bool]:
    """Checks if a join condition connects subset 1 and subset 2."""
    for cond in conditions:
        t1 = cond.get("left_table")
        t2 = cond.get("right_table")
        col2 = cond.get("right_column")
        col1 = cond.get("left_column")

        if t1 in s1 and t2 in s2:
            cond_repr = f"{t1}.{col1} = {t2}.{col2}"
            has_idx = (t2 in indexes) and (col2 in indexes[t2] if col2 else False)
            return cond_repr, has_idx
        if t2 in s1 and t1 in s2:
            cond_repr = f"{t2}.{col2} = {t1}.{col1}"
            has_idx = (t1 in indexes) and (col1 in indexes[t1] if col1 else False)
            return cond_repr, has_idx
    return None, False


def _estimate_join_cost(
    left_rows: int,
    left_cost: float,
    right_rows: int,
    right_cost: float,
    has_index_on_right: bool = False,
) -> Tuple[JoinPhysicalOperator, float]:
    """Calculates physical operator and cost for joining left and right inputs."""
    nlj_cost = left_cost + (right_cost * max(1, left_rows))
    hj_cost = left_cost + right_cost + 1.2 * (left_rows + right_rows)
    inj_cost = (
        left_cost + (left_rows * math.log2(max(2, right_rows)) * 0.5)
        if has_index_on_right
        else float("inf")
    )

    min_cost = min(nlj_cost, hj_cost, inj_cost)
    if min_cost == inj_cost:
        return JoinPhysicalOperator.INDEX_JOIN, inj_cost
    if min_cost == hj_cost:
        return JoinPhysicalOperator.HASH_JOIN, hj_cost
    return JoinPhysicalOperator.NESTED_LOOP_JOIN, nlj_cost


def _find_best_plan_for_subset(
    subset: List[str],
    dp_table: Dict[frozenset[str], JoinPlanNode],
    join_conditions: List[Dict[str, str]],
    indexes: Dict[str, Set[str]],
) -> Optional[JoinPlanNode]:
    """Finds best join plan partition for a given table subset."""
    best_plan: Optional[JoinPlanNode] = None
    subsets: List[List[str]] = []
    for r in range(1, len(subset)):
        for c in itertools.combinations(subset, r):
            subsets.append(list(c))

    for s1 in subsets:
        s2 = [t for t in subset if t not in s1]
        plan = _eval_split_plan(s1, s2, dp_table, join_conditions, indexes)
        if plan and (best_plan is None or plan.cost < best_plan.cost):
            best_plan = plan
    return best_plan


def _init_dp_table(
    tables: List[str],
    table_stats: Dict[str, TableStats],
) -> Dict[frozenset[str], JoinPlanNode]:
    """Initializes DP table with single-table scan plans."""
    dp: Dict[frozenset[str], JoinPlanNode] = {}
    for t in tables:
        rows = table_stats[t].total_rows if t in table_stats else 100
        dp[frozenset([t])] = JoinPlanNode(
            left=t,
            right="",
            operator=JoinPhysicalOperator.HASH_JOIN,
            cost=float(rows),
            estimated_rows=rows,
        )
    return dp


def _run_dp_enumeration(
    tables: List[str],
    dp_table: Dict[frozenset[str], JoinPlanNode],
    join_conditions: List[Dict[str, str]],
    indexes: Dict[str, Set[str]],
) -> None:
    """Executes bottom-up DP levels 2..N."""
    for size in range(2, len(tables) + 1):
        for comb in itertools.combinations(tables, size):
            subset = list(comb)
            best_plan = _find_best_plan_for_subset(
                subset, dp_table, join_conditions, indexes
            )
            if best_plan is not None:
                dp_table[frozenset(subset)] = best_plan


class DPJoinOptimizer:
    """
    Bottom-Up Dynamic Programming Join Order Optimizer.
    """

    @classmethod
    def optimize_join(
        cls,
        tables: List[str],
        join_conditions: List[Dict[str, str]],
        table_stats: Dict[str, TableStats],
        available_indexes: Optional[Dict[str, Set[str]]] = None,
    ) -> JoinPlanNode:
        """Computes the optimal JoinPlanNode for N tables using bottom-up DP."""
        if not tables:
            raise ValueError("Tables list cannot be empty")
        if len(tables) == 1:
            t = tables[0]
            rows = table_stats[t].total_rows if t in table_stats else 100
            return JoinPlanNode(
                left=t,
                right="",
                operator=JoinPhysicalOperator.HASH_JOIN,
                cost=float(rows),
                estimated_rows=rows,
            )

        indexes = available_indexes or {}
        dp_table = _init_dp_table(tables, table_stats)
        _run_dp_enumeration(tables, dp_table, join_conditions, indexes)
        return dp_table[frozenset(tables)]
