#!/usr/bin/env python3
"""
Cost Model and Execution Plan Types for Database Query Planner.
Computes I/O and CPU cost estimates for Table Scans, Index Scans, and Vector ANN paths.
"""

from enum import Enum
from typing import Optional


class PlanType(Enum):
    TABLE_SCAN = "TABLE_SCAN"
    INDEX_SCAN = "INDEX_SCAN"
    VECTOR_KNN = "VECTOR_KNN"
    HYBRID_KNN_FIRST = "HYBRID_KNN_FIRST"
    HYBRID_FILTER_FIRST = "HYBRID_FILTER_FIRST"


class CostModel:
    """
    Cost estimation model based on Disk Page I/O and CPU operation units.
    PAGE_IO_COST = 1.0
    CPU_TUPLE_COST = 0.01
    CPU_VECTOR_DIST_COST = 0.1
    """

    PAGE_IO_COST = 1.0
    CPU_TUPLE_COST = 0.01
    CPU_VECTOR_DIST_COST = 0.1
    PAGE_ROWS_ESTIMATE = 64  # Average rows stored per 4096-byte page

    @classmethod
    def estimate_table_scan_cost(cls, total_rows: int) -> float:
        """Estimates cost of a full table scan."""
        pages = max(1, total_rows // cls.PAGE_ROWS_ESTIMATE)
        io_cost = pages * cls.PAGE_IO_COST
        cpu_cost = total_rows * cls.CPU_TUPLE_COST
        return round(io_cost + cpu_cost, 3)

    @classmethod
    def estimate_index_scan_cost(
        cls, total_rows: int, selectivity: float, tree_height: Optional[int] = None
    ) -> float:
        """Estimates cost of a B+Tree index lookup and fetch."""
        if tree_height is None:
            height = 1 if total_rows < 500 else (2 if total_rows < 10000 else 3)
        else:
            height = tree_height
        index_io = height * cls.PAGE_IO_COST
        matched_rows = max(1, int(total_rows * selectivity))
        data_pages = max(1, matched_rows // cls.PAGE_ROWS_ESTIMATE)
        data_io = data_pages * cls.PAGE_IO_COST
        cpu_cost = matched_rows * cls.CPU_TUPLE_COST
        return round(index_io + data_io + cpu_cost, 3)

    @classmethod
    def estimate_vector_knn_cost(
        cls, total_rows: int, top_k: int, ef_search: int = 32
    ) -> float:
        """Estimates cost of an HNSW vector ANN traversal."""
        graph_hops = min(total_rows, ef_search * 2)
        dist_calcs = graph_hops * 16  # Approx M connections evaluated
        cpu_cost = dist_calcs * cls.CPU_VECTOR_DIST_COST
        return round(cpu_cost, 3)

    @classmethod
    def estimate_hybrid_cost(
        cls,
        total_rows: int,
        selectivity: float,
        top_k: int,
        has_index: bool,
    ) -> tuple[PlanType, float]:
        """
        Determines whether to execute Vector KNN first vs B+Tree Filter first.
        - High selectivity (very few matching rows, e.g. < 5%): Filter first then Vector Re-rank.
        - Low selectivity (many matching rows, e.g. > 20%): Vector KNN first then Filter.
        """
        filter_cost = (
            cls.estimate_index_scan_cost(total_rows, selectivity)
            if has_index
            else cls.estimate_table_scan_cost(total_rows)
        )
        filtered_rows = max(1, int(total_rows * selectivity))
        rerank_cost = filtered_rows * cls.CPU_VECTOR_DIST_COST
        filter_first_total = filter_cost + rerank_cost

        knn_cost = cls.estimate_vector_knn_cost(total_rows, top_k * 5)
        eval_filter_cost = (top_k * 5) * cls.CPU_TUPLE_COST
        knn_first_total = knn_cost + eval_filter_cost

        if filter_first_total < knn_first_total:
            return PlanType.HYBRID_FILTER_FIRST, round(filter_first_total, 3)
        else:
            return PlanType.HYBRID_KNN_FIRST, round(knn_first_total, 3)
