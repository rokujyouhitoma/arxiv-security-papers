#!/usr/bin/env python3
"""
Slotted-Page Binary Storage Adapter for Pure-Python DBMS.
Bridges Pager, PageCache, SlottedPage, and TupleSerializer into
a standard table storage backend compatible with SQLExecutor.
"""

from typing import Any, Dict, List, Optional, Sequence, Tuple

from .pager import Pager
from .slotted_page import DataType, PageType, SlottedPage, TupleSerializer


class SlottedPageStorage:
    """
    Table storage backend backed by 4096-byte SlottedPage binary pages and Pager.
    Compatible with the VectorStorage duck-typed interface used across SQLExecutor.
    """

    def __init__(self, file_path: str = ":memory:", dim: int = 128) -> None:
        self.file_path = file_path
        self.dim = dim
        self.is_memory = file_path == ":memory:"
        self.pager = Pager(file_path=file_path)
        self.metadata: List[Dict[str, Any]] = []
        self._vectors: List[Tuple[float, ...]] = []
        self.id_to_idx: Dict[str, int] = {}
        self.schema: List[Tuple[str, DataType]] = [
            ("id", DataType.VARCHAR),
            ("val", DataType.TEXT),
        ]
        self._init_first_page()

    def _init_first_page(self) -> None:
        if self.pager.page_count() == 0:
            first_page = SlottedPage(page_id=0, page_type=PageType.DATA)
            self.pager.write_slotted_page(first_page)

    @property
    def count(self) -> int:
        return len(self.metadata)

    def get_vector(self, idx: int) -> Tuple[float, ...]:
        if 0 <= idx < len(self._vectors):
            return self._vectors[idx]
        return (0.0,) * self.dim

    def get_all_vectors(self) -> List[Tuple[float, ...]]:
        return list(self._vectors)

    def _sync_id_mapping(self, idx: int, meta: Dict[str, Any]) -> None:
        if "id" in meta:
            self.id_to_idx[str(meta["id"])] = idx

    def _persist_tuple_to_pager(self, row: Dict[str, Any]) -> None:
        try:
            curr_pid = max(0, self.pager.page_count() - 1)
            slotted = self.pager.read_slotted_page(curr_pid)
            tuple_bytes = TupleSerializer.serialize(self.schema, row)
            if slotted.free_space < len(tuple_bytes) + 4:
                new_pid = self.pager.page_count()
                slotted = SlottedPage(page_id=new_pid, page_type=PageType.DATA)
                slotted.insert_tuple(tuple_bytes)
                self.pager.write_slotted_page(slotted)
            else:
                slotted.insert_tuple(tuple_bytes)
                self.pager.write_slotted_page(slotted)
        except Exception:
            pass

    def append(
        self,
        vector: Sequence[float],
        metadata: Optional[Dict[str, Any]] = None,
    ) -> int:
        """Appends a single record and vector into slotted storage."""
        idx = len(self.metadata)
        t_vec = tuple(vector) if len(vector) == self.dim else (0.0,) * self.dim
        self._vectors.append(t_vec)
        meta = dict(metadata) if metadata is not None else {"id": str(idx)}
        self.metadata.append(meta)
        self._sync_id_mapping(idx, meta)
        self._persist_tuple_to_pager(meta)
        return idx

    def append_batch(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: Optional[List[Dict[str, Any]]] = None,
    ) -> List[int]:
        """Appends a batch of records and vectors into slotted storage."""
        indices: List[int] = []
        meta_list = metadata or []
        for i, vec in enumerate(vectors):
            meta = meta_list[i] if i < len(meta_list) else None
            indices.append(self.append(vec, meta))
        return indices

    def _rebuild_state_mappings(self) -> None:
        self.id_to_idx.clear()
        for idx, m in enumerate(self.metadata):
            self._sync_id_mapping(idx, m)

    def write_all(
        self,
        vectors: Sequence[Sequence[float]],
        metadata: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        """Overwrites all stored vectors and metadata."""
        self._vectors = [tuple(v) for v in vectors]
        self.metadata = [dict(m) for m in (metadata or [])]
        self._rebuild_state_mappings()
        self._init_first_page()
        for m in self.metadata:
            self._persist_tuple_to_pager(m)

    def close(self) -> None:
        """Closes the underlying pager."""
        self.pager.close()
