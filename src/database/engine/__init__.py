#!/usr/bin/env python3
"""
Database Execution Engine Subsystem.
Exports Volcano-style streaming iterators and Vectorized batch execution operators.
"""

from .vectorized import (
    BatchIterator,
    ColumnBatch,
    VectorizedAggregation,
    VectorizedFilter,
    VectorizedProjection,
    VectorizedScan,
)
from .volcano import (
    FilterIterator,
    HashJoinIterator,
    IndexScanIterator,
    LimitIterator,
    NestedLoopJoinIterator,
    ProjectionIterator,
    SeqScanIterator,
    VolcanoIterator,
)

__all__ = [
    # Volcano Streaming Iterators
    "VolcanoIterator",
    "SeqScanIterator",
    "IndexScanIterator",
    "FilterIterator",
    "ProjectionIterator",
    "NestedLoopJoinIterator",
    "HashJoinIterator",
    "LimitIterator",
    # Vectorized Batch Engine
    "ColumnBatch",
    "BatchIterator",
    "VectorizedScan",
    "VectorizedFilter",
    "VectorizedProjection",
    "VectorizedAggregation",
]
