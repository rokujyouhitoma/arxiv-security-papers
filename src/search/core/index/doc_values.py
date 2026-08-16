#!/usr/bin/env python3
"""
Lucene-style DocValues Columnar Storage.
Stores per-document field values in columnar format for fast sorting and faceting.
"""

from collections import defaultdict
from typing import Any, Dict, Optional, Set


class DocValues:
    """
    Columnar storage mapping Field -> {DocID -> Value/Values}.
    Enables O(1) attribute lookup for sorting and aggregations.
    """

    def __init__(self) -> None:
        self.columns: Dict[str, Dict[str, Any]] = defaultdict(dict)

    def set_value(self, field: str, doc_id: str, value: Any) -> None:
        self.columns[field][doc_id] = value

    def get_value(self, field: str, doc_id: str) -> Optional[Any]:
        return self.columns.get(field, {}).get(doc_id)

    def get_column(self, field: str) -> Dict[str, Any]:
        return self.columns.get(field, {})

    def get_doc_ids_matching(self, field: str, target_val: Any) -> Set[str]:
        matched: Set[str] = set()
        col = self.columns.get(field, {})
        for did, val in col.items():
            if isinstance(val, (list, set, tuple)):
                if target_val in val:
                    matched.add(did)
            elif val == target_val:
                matched.add(did)
        return matched
