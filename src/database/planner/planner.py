#!/usr/bin/env python3
"""
Cost-Based Query Planner and EXPLAIN QUERY PLAN Engine.
Selects optimal scan strategies (B+Tree Index Scan vs Table Scan vs Vector Hybrid)
based on catalog statistics and estimated execution costs.
"""

from typing import Any, Dict, List, Optional, Set, Tuple

from ..sql.ast import SelectStatement
from .cost import CostModel, PlanType
from .join_optimizer import DPJoinOptimizer, JoinPlanNode
from .stats import TableStats


class ExecutionPlan:
    """Represents a chosen execution strategy with cost details."""

    def __init__(
        self,
        plan_type: PlanType,
        estimated_cost: float,
        table_name: str,
        selected_index: Optional[str] = None,
        index_column: Optional[str] = None,
        description: str = "",
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.plan_type = plan_type
        self.estimated_cost = estimated_cost
        self.table_name = table_name
        self.selected_index = selected_index
        self.index_column = index_column
        self.description = description
        self.details = details or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "plan_type": self.plan_type.value,
            "estimated_cost": self.estimated_cost,
            "table_name": self.table_name,
            "selected_index": self.selected_index,
            "index_column": self.index_column,
            "description": self.description,
            "details": self.details,
        }


class QueryPlanner:
    """
    Cost-Based Query Planner.
    Evaluates predicate selectivity and picks optimal physical scan operators.
    """

    @classmethod
    def _get_clause_col_op_val(cls, clause: Dict[str, Any]) -> Tuple[str, str, Any]:
        col = str(clause.get("field") or clause.get("column") or "")
        op = str(clause.get("op") or clause.get("operator") or "=")
        val = clause.get("value")
        return col, op, val

    @classmethod
    def _eval_clause_selectivity(
        cls,
        clause: Dict[str, Any],
        stats: TableStats,
        available_indexes: Dict[str, str],
    ) -> Tuple[Optional[str], Optional[str], Optional[float]]:
        col, op, val = cls._get_clause_col_op_val(clause)
        if col in available_indexes and col in stats.columns:
            sel = stats.columns[col].estimate_selectivity(op, val)
            return available_indexes[col], col, sel
        return None, None, None

    @classmethod
    def _scan_clauses(
        cls,
        where_clauses: List[Dict[str, Any]],
        stats: TableStats,
        available_indexes: Dict[str, str],
    ) -> Tuple[Optional[str], Optional[str], float]:
        best_index: Optional[str] = None
        best_col: Optional[str] = None
        min_selectivity = 1.0

        for clause in where_clauses:
            idx, col, sel = cls._eval_clause_selectivity(
                clause, stats, available_indexes
            )
            if sel is not None and sel < min_selectivity:
                min_selectivity, best_col, best_index = sel, col, idx

        return best_index, best_col, min_selectivity

    @classmethod
    def _find_best_indexed_column(
        cls,
        where_clauses: List[Dict[str, Any]],
        stats: Optional[TableStats],
        available_indexes: Dict[str, str],
    ) -> Tuple[Optional[str], Optional[str], float]:
        if not stats or not where_clauses:
            return None, None, 1.0
        return cls._scan_clauses(where_clauses, stats, available_indexes)

    @classmethod
    def _plan_vector_query(
        cls,
        stmt: SelectStatement,
        total_rows: int,
        best_index: Optional[str],
        best_col: Optional[str],
        min_selectivity: float,
    ) -> ExecutionPlan:
        top_k = stmt.knn_query.get("top_k", 10) if stmt.knn_query else 10
        table_name = stmt.table_name

        if not stmt.where_clauses:
            cost = CostModel.estimate_vector_knn_cost(total_rows, top_k)
            return ExecutionPlan(
                plan_type=PlanType.VECTOR_KNN,
                estimated_cost=cost,
                table_name=table_name,
                description=f"SCAN TABLE {table_name} USING VECTOR ANN (HNSW top_k={top_k})",
            )

        has_index = best_index is not None
        plan_type, cost = CostModel.estimate_hybrid_cost(
            total_rows=total_rows,
            selectivity=min_selectivity,
            top_k=top_k,
            has_index=has_index,
        )
        desc = (
            f"SEARCH TABLE {table_name} USING INDEX {best_index} ({best_col}) "
            f"THEN VECTOR RE-RANK (Filter-First)"
            if plan_type == PlanType.HYBRID_FILTER_FIRST
            else f"SCAN TABLE {table_name} USING VECTOR ANN THEN FILTER (KNN-First)"
        )
        return ExecutionPlan(
            plan_type=plan_type,
            estimated_cost=cost,
            table_name=table_name,
            selected_index=best_index,
            index_column=best_col,
            description=desc,
        )

    @classmethod
    def _plan_relational_query(
        cls,
        table_name: str,
        total_rows: int,
        best_index: Optional[str],
        best_col: Optional[str],
        min_selectivity: float,
    ) -> ExecutionPlan:
        table_scan_cost = CostModel.estimate_table_scan_cost(total_rows)

        if best_index is not None and min_selectivity < 0.40:
            index_scan_cost = CostModel.estimate_index_scan_cost(
                total_rows, min_selectivity
            )
            if index_scan_cost < table_scan_cost:
                return ExecutionPlan(
                    plan_type=PlanType.INDEX_SCAN,
                    estimated_cost=index_scan_cost,
                    table_name=table_name,
                    selected_index=best_index,
                    index_column=best_col,
                    description=f"SEARCH TABLE {table_name} USING INDEX {best_index} ({best_col})",
                )

        return ExecutionPlan(
            plan_type=PlanType.TABLE_SCAN,
            estimated_cost=table_scan_cost,
            table_name=table_name,
            description=f"SCAN TABLE {table_name} (FULL SCAN)",
        )

    @classmethod
    def plan_select(
        cls,
        stmt: SelectStatement,
        stats: Optional[TableStats],
        available_indexes: Optional[Dict[str, str]] = None,
    ) -> ExecutionPlan:
        table_name = stmt.table_name
        total_rows = stats.total_rows if stats else 100
        available_indexes = available_indexes or {}

        best_index, best_col, min_sel = cls._find_best_indexed_column(
            stmt.where_clauses, stats, available_indexes
        )

        if stmt.knn_query:
            return cls._plan_vector_query(
                stmt, total_rows, best_index, best_col, min_sel
            )

        return cls._plan_relational_query(
            table_name, total_rows, best_index, best_col, min_sel
        )

    @classmethod
    def plan_join(
        cls,
        tables: List[str],
        join_conditions: List[Dict[str, str]],
        table_stats: Dict[str, TableStats],
        available_indexes: Optional[Dict[str, Set[str]]] = None,
    ) -> JoinPlanNode:
        """
        Uses Dynamic Programming (DP) join order optimizer to plan multi-table joins.
        """
        return DPJoinOptimizer.optimize_join(
            tables=tables,
            join_conditions=join_conditions,
            table_stats=table_stats,
            available_indexes=available_indexes,
        )

    @classmethod
    def explain(
        cls,
        stmt: SelectStatement,
        stats: Optional[TableStats],
        available_indexes: Optional[Dict[str, str]] = None,
    ) -> List[Dict[str, Any]]:
        """Generates SQLite-compatible EXPLAIN QUERY PLAN rows."""
        plan = cls.plan_select(stmt, stats, available_indexes)
        return [
            {
                "id": 1,
                "parent": 0,
                "notused": 0,
                "detail": plan.description,
                "estimated_cost": plan.estimated_cost,
                "plan_type": plan.plan_type.value,
            }
        ]
