#!/usr/bin/env python3
"""
Lucene-style Stored Fields Row Storage.
Stores complete original document payloads for hit retrieval and display.
"""

from typing import Any, Dict, List, Optional


class StoredFields:
    """Row-oriented document storage mapping DocID -> Document Dictionary."""

    def __init__(self) -> None:
        self.doc_store: Dict[str, Dict[str, Any]] = {}

    def put_document(self, doc_id: str, document: Dict[str, Any]) -> None:
        self.doc_store[doc_id] = document

    def get_document(self, doc_id: str) -> Optional[Dict[str, Any]]:
        return self.doc_store.get(doc_id)

    def count(self) -> int:
        return len(self.doc_store)

    def all_documents(self) -> List[Dict[str, Any]]:
        return list(self.doc_store.values())
