#!/usr/bin/env python3
"""
Vectorized Batch Execution Engine.
Processes data in columnar batches (e.g. 1024 rows per batch) to minimize
Python interpreter overhead and optimize memory locality.
"""

import abc
from typing import Any, Callable, Dict, List, Optional, Set, Tuple


class ColumnBatch:
    """
    Represents a columnar chunk of rows (typically 1024 rows).
    Columns are stored as parallel arrays for vectorized evaluation.
    """

    def __init__(
        self,
        columns: Dict[str, List[Any]],
        num_rows: Optional[int] = None,
        selection_vector: Optional[List[int]] = None,
    ) -> None:
        self.columns = columns
        if num_rows is not None:
            self.num_rows = num_rows
        elif columns:
            first_col = next(iter(columns.values()))
            self.num_rows = len(first_col)
        else:
            self.num_rows = 0

        self.selection_vector = selection_vector

    @property
    def active_rows_count(self) -> int:
        """Returns the number of active rows considering the selection vector."""
        if self.selection_vector is not None:
            return len(self.selection_vector)
        return self.num_rows

    def get_column(self, col_name: str) -> List[Any]:
        """Returns the column values filtered by the selection vector."""
        raw = self.columns.get(col_name, [])
        if self.selection_vector is None:
            return raw
        return [raw[i] for i in self.selection_vector if i < len(raw)]

    def to_rows(self) -> List[Dict[str, Any]]:
        """Converts column batch into list of row dictionaries."""
        indices = (
            self.selection_vector
            if self.selection_vector is not None
            else list(range(self.num_rows))
        )
        rows: List[Dict[str, Any]] = []
        for idx in indices:
            row = {col: self.columns[col][idx] for col in self.columns}
            rows.append(row)
        return rows

    def filter_by_mask(self, mask: List[bool]) -> "ColumnBatch":
        """Returns a new ColumnBatch with updated selection vector based on a boolean mask."""
        current_indices = (
            self.selection_vector
            if self.selection_vector is not None
            else list(range(self.num_rows))
        )
        new_indices = [idx for idx, keep in zip(current_indices, mask) if keep]
        return ColumnBatch(
            columns=self.columns,
            num_rows=self.num_rows,
            selection_vector=new_indices,
        )

    def project(self, target_columns: List[str]) -> "ColumnBatch":
        """Returns a new ColumnBatch with only the specified columns."""
        new_cols = {
            col: self.columns[col] for col in target_columns if col in self.columns
        }
        return ColumnBatch(
            columns=new_cols,
            num_rows=self.num_rows,
            selection_vector=self.selection_vector,
        )


class BatchIterator(abc.ABC):
    """Abstract base class for vectorized batch operators."""

    @abc.abstractmethod
    def open(self) -> None:
        """Initializes the batch iterator."""
        pass

    @abc.abstractmethod
    def next_batch(self) -> Optional[ColumnBatch]:
        """Fetches the next columnar batch (or None if exhausted)."""
        pass

    @abc.abstractmethod
    def close(self) -> None:
        """Releases batch iterator resources."""
        pass


class VectorizedScan(BatchIterator):
    """Vectorized table scanner reading rows in batches of batch_size."""

    def __init__(
        self,
        rows: List[Dict[str, Any]],
        batch_size: int = 1024,
    ) -> None:
        self.rows = rows
        self.batch_size = batch_size
        self._cursor: int = 0
        self._is_open: bool = False

    def open(self) -> None:
        self._cursor = 0
        self._is_open = True

    def next_batch(self) -> Optional[ColumnBatch]:
        if not self._is_open or self._cursor >= len(self.rows):
            return None

        slice_rows = self.rows[self._cursor : self._cursor + self.batch_size]
        self._cursor += len(slice_rows)

        if not slice_rows:
            return None

        all_keys: Set[str] = set()
        for r in slice_rows:
            all_keys.update(r.keys())

        columns: Dict[str, List[Any]] = {
            k: [r.get(k) for r in slice_rows] for k in all_keys
        }
        return ColumnBatch(columns=columns, num_rows=len(slice_rows))

    def close(self) -> None:
        self._is_open = False
        self._cursor = 0


class VectorizedFilter(BatchIterator):
    """Vectorized filter evaluating predicate over column arrays."""

    def __init__(
        self,
        child: BatchIterator,
        predicate: Callable[[ColumnBatch], List[bool]],
    ) -> None:
        self.child = child
        self.predicate = predicate

    def open(self) -> None:
        self.child.open()

    def next_batch(self) -> Optional[ColumnBatch]:
        while True:
            batch = self.child.next_batch()
            if batch is None:
                return None
            mask = self.predicate(batch)
            filtered = batch.filter_by_mask(mask)
            if filtered.active_rows_count > 0:
                return filtered

    def close(self) -> None:
        self.child.close()


class VectorizedProjection(BatchIterator):
    """Vectorized column projection."""

    def __init__(
        self,
        child: BatchIterator,
        columns: List[str],
    ) -> None:
        self.child = child
        self.columns = columns

    def open(self) -> None:
        self.child.open()

    def next_batch(self) -> Optional[ColumnBatch]:
        batch = self.child.next_batch()
        if batch is None:
            return None
        return batch.project(self.columns)

    def close(self) -> None:
        self.child.close()


def _collect_column_stats(
    iterator: BatchIterator,
    column_name: str,
) -> Tuple[int, float, Optional[Any], Optional[Any]]:
    """Iterates batches and accumulates count, sum, min, max."""
    count = 0
    total_sum = 0.0
    min_val: Optional[Any] = None
    max_val: Optional[Any] = None

    iterator.open()
    try:
        while True:
            batch = iterator.next_batch()
            if batch is None:
                break
            for v in batch.get_column(column_name):
                if v is None:
                    continue
                count += 1
                if isinstance(v, (int, float)):
                    total_sum += float(v)
                if min_val is None or v < min_val:
                    min_val = v
                if max_val is None or v > max_val:
                    max_val = v
    finally:
        iterator.close()

    return count, total_sum, min_val, max_val


def _format_aggregate_result(
    agg: str,
    count: int,
    total_sum: float,
    min_val: Optional[Any],
    max_val: Optional[Any],
) -> Optional[Any]:
    """Formats final scalar result based on aggregate function."""
    if agg == "COUNT":
        return count
    if count == 0:
        return None
    if agg == "SUM":
        return total_sum
    if agg == "AVG":
        return total_sum / count
    if agg == "MIN":
        return min_val
    if agg == "MAX":
        return max_val
    raise ValueError(f"Unsupported aggregate function: {agg}")


class VectorizedAggregation:
    """
    Vectorized analytics aggregator calculating COUNT, SUM, AVG, MIN, MAX
    across streamed column batches.
    """

    @classmethod
    def aggregate(
        cls,
        iterator: BatchIterator,
        column_name: str,
        agg_func: str,
    ) -> Optional[Any]:
        """Computes aggregate over the batch iterator."""
        count, total_sum, min_val, max_val = _collect_column_stats(
            iterator, column_name
        )
        return _format_aggregate_result(
            agg_func.upper(), count, total_sum, min_val, max_val
        )
