#!/usr/bin/env python3
"""
Volcano Iterator Execution Model (Pull-Based Streaming).
Implements the standard open() / next() / close() iterator interface
for streaming tuple execution without materializing entire intermediate sets in memory.
"""

import abc
from typing import Any, Callable, Dict, List, Optional


class VolcanoIterator(abc.ABC):
    """Abstract base class for all Volcano-style physical execution operators."""

    @abc.abstractmethod
    def open(self) -> None:
        """Initializes the operator and allocates necessary execution resources."""
        pass

    @abc.abstractmethod
    def next(self) -> Optional[Dict[str, Any]]:
        """
        Fetches the next output tuple from the operator pipeline.
        Returns None when no more tuples are available.
        """
        pass

    @abc.abstractmethod
    def close(self) -> None:
        """Releases all resources, closes child operators, and cleans up state."""
        pass


class SeqScanIterator(VolcanoIterator):
    """Sequentially scans a collection or table rows one by one."""

    def __init__(self, rows: List[Dict[str, Any]]) -> None:
        self.rows = rows
        self._cursor: int = 0
        self._is_open: bool = False

    def open(self) -> None:
        self._cursor = 0
        self._is_open = True

    def next(self) -> Optional[Dict[str, Any]]:
        if not self._is_open or self._cursor >= len(self.rows):
            return None
        row = self.rows[self._cursor]
        self._cursor += 1
        return row

    def close(self) -> None:
        self._is_open = False
        self._cursor = 0


class IndexScanIterator(VolcanoIterator):
    """Scans rows matching an index key or range."""

    def __init__(
        self,
        index_data: List[Dict[str, Any]],
        filter_func: Optional[Callable[[Dict[str, Any]], bool]] = None,
    ) -> None:
        self.index_data = index_data
        self.filter_func = filter_func
        self._cursor: int = 0
        self._is_open: bool = False

    def open(self) -> None:
        self._cursor = 0
        self._is_open = True

    def next(self) -> Optional[Dict[str, Any]]:
        if not self._is_open:
            return None
        while self._cursor < len(self.index_data):
            row = self.index_data[self._cursor]
            self._cursor += 1
            if self.filter_func is None or self.filter_func(row):
                return row
        return None

    def close(self) -> None:
        self._is_open = False
        self._cursor = 0


class FilterIterator(VolcanoIterator):
    """Filters tuples produced by a child operator based on a predicate."""

    def __init__(
        self,
        child: VolcanoIterator,
        predicate: Callable[[Dict[str, Any]], bool],
    ) -> None:
        self.child = child
        self.predicate = predicate

    def open(self) -> None:
        self.child.open()

    def next(self) -> Optional[Dict[str, Any]]:
        while True:
            row = self.child.next()
            if row is None:
                return None
            if self.predicate(row):
                return row

    def close(self) -> None:
        self.child.close()


class ProjectionIterator(VolcanoIterator):
    """Projects specific columns from child tuples."""

    def __init__(
        self,
        child: VolcanoIterator,
        columns: List[str],
    ) -> None:
        self.child = child
        self.columns = columns

    def open(self) -> None:
        self.child.open()

    def next(self) -> Optional[Dict[str, Any]]:
        row = self.child.next()
        if row is None:
            return None
        return {col: row.get(col) for col in self.columns}

    def close(self) -> None:
        self.child.close()


class NestedLoopJoinIterator(VolcanoIterator):
    """Streaming nested loop join over left and right children."""

    def __init__(
        self,
        left_child: VolcanoIterator,
        right_child_factory: Callable[[], VolcanoIterator],
        join_predicate: Callable[[Dict[str, Any], Dict[str, Any]], bool],
    ) -> None:
        self.left_child = left_child
        self.right_child_factory = right_child_factory
        self.join_predicate = join_predicate
        self._current_left: Optional[Dict[str, Any]] = None
        self._current_right_iter: Optional[VolcanoIterator] = None

    def open(self) -> None:
        self.left_child.open()
        self._current_left = self.left_child.next()
        if self._current_left is not None:
            self._current_right_iter = self.right_child_factory()
            self._current_right_iter.open()
        else:
            self._current_right_iter = None

    def next(self) -> Optional[Dict[str, Any]]:
        while self._current_left is not None and self._current_right_iter is not None:
            right_row = self._current_right_iter.next()
            if right_row is not None:
                if self.join_predicate(self._current_left, right_row):
                    merged = dict(self._current_left)
                    merged.update(right_row)
                    return merged
            else:
                self._current_right_iter.close()
                self._current_left = self.left_child.next()
                if self._current_left is not None:
                    self._current_right_iter = self.right_child_factory()
                    self._current_right_iter.open()
                else:
                    self._current_right_iter = None
        return None

    def close(self) -> None:
        self.left_child.close()
        if self._current_right_iter is not None:
            self._current_right_iter.close()
            self._current_right_iter = None
        self._current_left = None


class HashJoinIterator(VolcanoIterator):
    """
    Equi-Join using in-memory hash table for the build side
    and pull-based streaming for the probe side.
    """

    def __init__(
        self,
        probe_child: VolcanoIterator,
        build_child: VolcanoIterator,
        probe_key: str,
        build_key: str,
    ) -> None:
        self.probe_child = probe_child
        self.build_child = build_child
        self.probe_key = probe_key
        self.build_key = build_key
        self._hash_table: Dict[Any, List[Dict[str, Any]]] = {}
        self._current_probe_row: Optional[Dict[str, Any]] = None
        self._match_buffer: List[Dict[str, Any]] = []
        self._match_idx: int = 0

    def open(self) -> None:
        # 1. Build Phase
        self._hash_table.clear()
        self.build_child.open()
        while True:
            row = self.build_child.next()
            if row is None:
                break
            k = row.get(self.build_key)
            if k is not None:
                if k not in self._hash_table:
                    self._hash_table[k] = []
                self._hash_table[k].append(row)
        self.build_child.close()

        # 2. Probe Phase initialization
        self.probe_child.open()
        self._current_probe_row = None
        self._match_buffer = []
        self._match_idx = 0

    def next(self) -> Optional[Dict[str, Any]]:
        while True:
            if self._match_idx < len(self._match_buffer):
                matched_build_row = self._match_buffer[self._match_idx]
                self._match_idx += 1
                if self._current_probe_row is not None:
                    res = dict(self._current_probe_row)
                    res.update(matched_build_row)
                    return res

            self._current_probe_row = self.probe_child.next()
            if self._current_probe_row is None:
                return None

            probe_k = self._current_probe_row.get(self.probe_key)
            if probe_k in self._hash_table:
                self._match_buffer = self._hash_table[probe_k]
                self._match_idx = 0
            else:
                self._match_buffer = []
                self._match_idx = 0

    def close(self) -> None:
        self.probe_child.close()
        self._hash_table.clear()
        self._match_buffer = []
        self._current_probe_row = None


class LimitIterator(VolcanoIterator):
    """Limits the number of output tuples with optional offset."""

    def __init__(
        self,
        child: VolcanoIterator,
        limit: int,
        offset: int = 0,
    ) -> None:
        self.child = child
        self.limit = limit
        self.offset = offset
        self._emitted: int = 0
        self._skipped: int = 0

    def open(self) -> None:
        self.child.open()
        self._emitted = 0
        self._skipped = 0

    def next(self) -> Optional[Dict[str, Any]]:
        while self._skipped < self.offset:
            row = self.child.next()
            if row is None:
                return None
            self._skipped += 1

        if self._emitted >= self.limit:
            return None

        row = self.child.next()
        if row is not None:
            self._emitted += 1
            return row
        return None

    def close(self) -> None:
        self.child.close()
